using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Robust.Shared;
using Robust.Shared.Configuration;
using Robust.Shared.IoC;
using Robust.Shared.Log;
using Robust.Shared.Network;

namespace Content.Server.Connection
{
    /// <summary>
    ///     SS14-fork implementation of <see cref="IRemoteAddressOverride"/>
    ///     that talks to the ss14-wrapper's UDS LOOKUP API (spec
    ///     dotfiles-9g1 §4.2 wire format).
    /// </summary>
    /// <remarks>
    ///     <para>
    ///         Wire format (per spec §4.2 + the Go-side wrapper at
    ///         <c>~/dotfiles/ss14-wrapper/wrapper/api.go</c>):
    ///         <list type="bullet">
    ///             <item>Request: <c>"LOOKUP &lt;proto&gt; &lt;local-port&gt;\n"</c></item>
    ///             <item>Response: <c>"OK &lt;real-ip&gt;:&lt;real-port&gt;\n"</c></item>
    ///             <item>Response: <c>"MISS\n"</c></item>
    ///             <item>Response: <c>"ERR &lt;msg&gt;\n"</c></item>
    ///         </list>
    ///     </para>
    ///     <para>
    ///         Gated by <see cref="CVars.NetUseWrapperRemoteAddress"/>
    ///         (default false). When the cvar is false, <see cref="Lookup"/>
    ///         short-circuits — no UDS connect attempted, no allocations,
    ///         vanilla behavior. The cvar is sampled on EVERY call so
    ///         operations can toggle it live for debugging.
    ///     </para>
    ///     <para>
    ///         Read-timeout: 200ms. Any IO failure / parse failure /
    ///         timeout returns null (caller falls back to the raw
    ///         endpoint per spec §3.9 graceful-degradation). Warnings
    ///         are rate-limited to one per minute so a crashed wrapper
    ///         doesn't flood the log.
    ///     </para>
    ///     <para>
    ///         Always-registered in <see cref="IoC.ServerContentIoC"/>;
    ///         the cvar — not the IoC registration — gates the actual
    ///         UDS traffic. This means
    ///         <c>IoCManager.Resolve&lt;IRemoteAddressOverride&gt;()</c>
    ///         always returns this instance, but it no-ops cheaply when
    ///         the wrapper isn't in use.
    ///     </para>
    /// </remarks>
    public sealed class Ss14WrapperRemoteAddressOverride : IRemoteAddressOverride
    {
        // Wrapper UDS read timeout. Spec says "short timeout (e.g. 200ms)";
        // the LOOKUP API is local-only + answers in well under 1ms when
        // healthy, so 200ms is comfortable headroom even under load.
        internal const int ReadTimeoutMs = 200;

        // Maximum bytes we'll read from a single UDS response. The wrapper
        // replies in one short line; we cap to defend against a misbehaving
        // (or hostile) UDS peer sending unbounded data.
        internal const int MaxReplyBytes = 256;

        // Response wire prefixes / sentinels from spec §4.2 + wrapper api.go.
        internal const string ReplyOkPrefix = "OK ";
        internal const string ReplyMiss = "MISS";
        internal const string ReplyErrPrefix = "ERR ";

        [Dependency] private readonly IConfigurationManager _cfg = default!;
        [Dependency] private readonly ILogManager _logMan = default!;

        // Sawmill is created lazily because [Dependency] resolves before
        // _logMan is usable in some IoC scenarios. Initialize on first use.
        private ISawmill? _sawmill;

        // Per-instance rate limiter for the "UDS failed" warning. Mirrors
        // NetManager's rate-limit pattern so a crashed wrapper doesn't
        // flood the log on every NetChannel read.
        private long _lastWarningTicks;

        /// <inheritdoc />
        public IPEndPoint? Lookup(string protocol, IPEndPoint observedEndpoint)
        {
            // Cvar-gate FIRST — when the wrapper isn't deployed we must
            // not even open the UDS (test TC10 / WrapperCvar_DefaultFalse_DoesNotConnectUds).
            if (!_cfg.GetCVar(CVars.NetUseWrapperRemoteAddress))
                return null;

            var sockPath = _cfg.GetCVar(CVars.NetWrapperSocket);
            if (string.IsNullOrEmpty(sockPath))
                return null;

            try
            {
                return LookupViaSocket(sockPath, protocol, observedEndpoint.Port);
            }
            catch (Exception ex)
            {
                LogWarningRateLimited("ss14-wrapper UDS lookup failed", ex);
                return null;
            }
        }

        /// <summary>
        ///     Open a single UDS connection, send a LOOKUP request, parse
        ///     the reply, return the parsed endpoint or null on MISS / ERR.
        ///     Any thrown exception escapes to <see cref="Lookup"/>'s
        ///     catch — which downgrades to null + rate-limited warning.
        /// </summary>
        /// <remarks>
        ///     Internal+virtual-equivalent NOT used; instead the wire
        ///     parser is split out (<see cref="ParseReply"/>) for direct
        ///     test coverage. Connection itself is exercised end-to-end
        ///     via a stub UDS server in
        ///     <c>Ss14WrapperRemoteAddressOverrideTests</c>.
        /// </remarks>
        internal static IPEndPoint? LookupViaSocket(string sockPath, string protocol, int localPort, int timeoutMs = ReadTimeoutMs)
        {
            using var sock = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            {
                ReceiveTimeout = timeoutMs,
                SendTimeout = timeoutMs,
            };

            sock.Connect(new UnixDomainSocketEndPoint(sockPath));

            // Spec §4.2 wire format. Case-sensitive, LF (not CRLF),
            // single space separator — verified by test
            // Lookup_RequestWireFormat_MatchesSpec.
            var req = Encoding.ASCII.GetBytes($"LOOKUP {protocol} {localPort}\n");
            sock.Send(req);

            // Read up to MaxReplyBytes or one full line (terminated by '\n').
            // We don't use StreamReader so that the read-timeout above
            // actually fires (StreamReader buffers indefinitely on slow
            // peers; raw Socket.Receive honors ReceiveTimeout).
            var buf = new byte[MaxReplyBytes];
            var total = 0;
            while (total < MaxReplyBytes)
            {
                var n = sock.Receive(buf, total, MaxReplyBytes - total, SocketFlags.None);
                if (n <= 0)
                    break;
                total += n;
                // Stop at first newline — the wrapper replies one short line.
                if (Array.IndexOf(buf, (byte)'\n', 0, total) >= 0)
                    break;
            }

            if (total == 0)
                return null;

            return ParseReply(Encoding.ASCII.GetString(buf, 0, total));
        }

        /// <summary>
        ///     Parse a single LOOKUP reply line.
        ///     <list type="bullet">
        ///         <item><c>"OK 1.2.3.4:5678\n"</c> → <c>IPEndPoint(1.2.3.4, 5678)</c></item>
        ///         <item><c>"MISS\n"</c> → null</item>
        ///         <item><c>"ERR ...\n"</c> → null</item>
        ///         <item>garbled / unknown → null</item>
        ///     </list>
        ///     Internal so tests can exercise wire-format parsing without
        ///     standing up a UDS.
        /// </summary>
        internal static IPEndPoint? ParseReply(string reply)
        {
            // Trim ALL trailing CR/LF — the wrapper writes "\n" but be
            // defensive in case a future revision uses "\r\n".
            var line = reply.TrimEnd('\r', '\n');

            if (string.IsNullOrEmpty(line))
                return null;

            if (line == ReplyMiss || line.StartsWith(ReplyErrPrefix, StringComparison.Ordinal))
                return null;

            if (line.StartsWith(ReplyOkPrefix, StringComparison.Ordinal))
            {
                var payload = line.AsSpan(ReplyOkPrefix.Length).TrimEnd();
                if (IPEndPoint.TryParse(payload, out var ep))
                    return ep;
            }

            // Unknown shape — fall back to null per spec §3.9.
            return null;
        }

        private void LogWarningRateLimited(string what, Exception ex)
        {
            var nowTicks = DateTime.UtcNow.Ticks;
            var lastTicks = Interlocked.Read(ref _lastWarningTicks);
            if (nowTicks - lastTicks <= TimeSpan.TicksPerMinute)
                return;
            if (Interlocked.CompareExchange(ref _lastWarningTicks, nowTicks, lastTicks) != lastTicks)
                return;

            _sawmill ??= _logMan.GetSawmill("ss14-wrapper");
            _sawmill.Warning(
                "{What} (subsequent failures suppressed for 60s): {Err}",
                what, ex.Message);
        }
    }
}
