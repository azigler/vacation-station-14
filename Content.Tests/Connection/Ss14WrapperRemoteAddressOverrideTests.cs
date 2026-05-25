#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Content.Server.Connection;
using NUnit.Framework;

namespace Content.Tests.Connection
{
    /// <summary>
    ///     Layer 2 implementation tests for
    ///     <see cref="Ss14WrapperRemoteAddressOverride"/> per
    ///     <c>~/dotfiles/ss14-wrapper/docs/ss14-patch-tests.md</c>.
    ///
    ///     These tests exercise the wire-format parser
    ///     (<see cref="Ss14WrapperRemoteAddressOverride.ParseReply"/>)
    ///     directly for fast, hermetic coverage of every reply shape,
    ///     plus an end-to-end UDS round-trip against an in-process stub
    ///     UDS server for the connect / send / receive / parse pipeline.
    ///
    ///     Tests that need a UDS use a per-test tempfile path under
    ///     <c>Path.GetTempPath()</c>; if that path would exceed the
    ///     macOS 104-byte limit (see ss14-patch-tests.md
    ///     "UDS path collisions"), the test is skipped with a clear
    ///     reason rather than failing spuriously.
    /// </summary>
    [TestFixture]
    [TestOf(typeof(Ss14WrapperRemoteAddressOverride))]
    public sealed class Ss14WrapperRemoteAddressOverrideTests
    {
        // -- Wire-format parser tests (no UDS needed) ------------------------

        /// <summary>TC: Lookup_HappyPath_Returns_ParsedEndpoint (parser-half)
        /// — given a canonical OK reply, the parser returns the parsed endpoint.</summary>
        [Test]
        public void ParseReply_HappyPath_ReturnsParsedEndpoint()
        {
            var ep = Ss14WrapperRemoteAddressOverride.ParseReply("OK 203.0.113.5:54321\n");
            Assert.That(ep, Is.Not.Null);
            Assert.That(ep!.Address.ToString(), Is.EqualTo("203.0.113.5"));
            Assert.That(ep.Port, Is.EqualTo(54321));
        }

        /// <summary>TC: Lookup_MissReply_ReturnsNull (parser-half)</summary>
        [Test]
        public void ParseReply_MissReply_ReturnsNull()
        {
            Assert.That(Ss14WrapperRemoteAddressOverride.ParseReply("MISS\n"), Is.Null);
        }

        /// <summary>TC: Lookup_GarbledReply_ReturnsNull_LogsWarning (parser-half)
        /// — a reply with neither OK / MISS / ERR returns null.
        /// The "logs warning" half is covered by the throwing-override
        /// rate-limit test in Layer 3 (the failure pathway lives in
        /// the calling try/catch, not in ParseReply itself).</summary>
        [Test]
        public void ParseReply_GarbledReply_ReturnsNull()
        {
            Assert.Multiple(() =>
            {
                Assert.That(Ss14WrapperRemoteAddressOverride.ParseReply("GARBLED\n"), Is.Null);
                Assert.That(Ss14WrapperRemoteAddressOverride.ParseReply("OK not-an-endpoint\n"), Is.Null);
                Assert.That(Ss14WrapperRemoteAddressOverride.ParseReply(""), Is.Null);
                Assert.That(Ss14WrapperRemoteAddressOverride.ParseReply("\n"), Is.Null);
            });
        }

        /// <summary>TC: ParseReply ERR returns null (spec §4.2 ERR sentinel)</summary>
        [Test]
        public void ParseReply_ErrReply_ReturnsNull()
        {
            Assert.That(
                Ss14WrapperRemoteAddressOverride.ParseReply("ERR bad request\n"),
                Is.Null);
        }

        /// <summary>TC: ParseReply tolerates CRLF and bare LF
        /// — defensive: the spec says LF (not CRLF), but a future revision
        /// or a debug-injected reply with CRLF must not break parsing.</summary>
        [Test]
        public void ParseReply_TrimsTrailingCrlf()
        {
            var lf = Ss14WrapperRemoteAddressOverride.ParseReply("OK 203.0.113.5:54321\n");
            var crlf = Ss14WrapperRemoteAddressOverride.ParseReply("OK 203.0.113.5:54321\r\n");
            Assert.That(crlf, Is.EqualTo(lf));
        }

        // -- End-to-end UDS round-trip tests --------------------------------

        /// <summary>TC: Lookup_HappyPath_Returns_ParsedEndpoint (full UDS round-trip)</summary>
        [Test]
        public void LookupViaSocket_HappyPath_ReturnsParsedEndpoint()
        {
            using var stub = StubUdsServer.Start(
                replyFor: req => req == "LOOKUP udp 33000" ? "OK 203.0.113.5:54321\n" : "MISS\n");

            var ep = Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 33000);

            Assert.That(ep, Is.Not.Null);
            Assert.That(ep!.Address.ToString(), Is.EqualTo("203.0.113.5"));
            Assert.That(ep.Port, Is.EqualTo(54321));
        }

        /// <summary>TC: Lookup_MissReply_ReturnsNull (full UDS round-trip)</summary>
        [Test]
        public void LookupViaSocket_MissReply_ReturnsNull()
        {
            using var stub = StubUdsServer.Start(replyFor: _ => "MISS\n");
            var ep = Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 9999);
            Assert.That(ep, Is.Null);
        }

        /// <summary>TC: Lookup_GarbledReply_ReturnsNull_LogsWarning (UDS half)</summary>
        [Test]
        public void LookupViaSocket_GarbledReply_ReturnsNull()
        {
            using var stub = StubUdsServer.Start(replyFor: _ => "GARBLED-RESPONSE-DATA\n");
            var ep = Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 33000);
            Assert.That(ep, Is.Null);
        }

        /// <summary>TC: Lookup_ConnectFails_ReturnsNull_LogsWarning
        /// — when the socket path doesn't exist, Connect throws.
        /// LookupViaSocket re-throws (the wrapping Lookup catches);
        /// here we assert the wire-level method throws so callers KNOW
        /// to fall back. The throwing-override-fallback path is
        /// independently tested in the Layer 3 helper test.</summary>
        [Test]
        public void LookupViaSocket_ConnectFails_Throws()
        {
            var noSuchPath = Path.Combine(Path.GetTempPath(), $"ss14-noexist-{Guid.NewGuid()}.sock");
            Assert.Throws<SocketException>(
                () => Ss14WrapperRemoteAddressOverride.LookupViaSocket(noSuchPath, "udp", 33000));
        }

        /// <summary>TC: Lookup_SocketTimeout_ReturnsNull
        /// — stub accepts but never replies; the configured ReceiveTimeout
        /// fires. LookupViaSocket throws a SocketException; the wrapping
        /// Lookup catches that and returns null. We assert the throw shape
        /// so we know the timeout machinery works.</summary>
        [Test]
        public void LookupViaSocket_SocketTimeout_Throws()
        {
            using var stub = StubUdsServer.Start(
                replyFor: _ => null!, // null reply = stub never writes
                holdConnectionMs: 5000);

            var sw = System.Diagnostics.Stopwatch.StartNew();
            Assert.Throws<SocketException>(
                () => Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 33000));
            sw.Stop();
            // Must time out close to ReadTimeoutMs (200ms) — well under the
            // 5s holdConnectionMs, proving the timeout actually fires.
            Assert.That(sw.ElapsedMilliseconds, Is.LessThan(2000),
                "timeout MUST fire within ~ReadTimeoutMs, not block on the slow peer");
        }

        /// <summary>TC: Lookup_ReplyTooLong_Truncated_StillSafe
        /// — a 100KB reply must not crash; it gets truncated by
        /// MaxReplyBytes and parsed (which will return null for garbled).</summary>
        [Test]
        public void LookupViaSocket_ReplyTooLong_Truncated_DoesNotThrow()
        {
            using var stub = StubUdsServer.Start(
                replyFor: _ => new string('A', 100_000) + "\n");

            IPEndPoint? ep = null;
            Assert.DoesNotThrow(
                () => ep = Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 33000));
            // The truncated buffer starts with "AAAA..." — neither OK / MISS / ERR.
            Assert.That(ep, Is.Null);
        }

        /// <summary>TC: Lookup_ConcurrentInvocations_Serialize
        /// — 10 concurrent Lookup calls, stub serves each with a
        /// port-encoded IP reply. All 10 return distinct endpoints, no
        /// cross-contamination.</summary>
        [Test]
        public void LookupViaSocket_ConcurrentInvocations_NoCrossContamination()
        {
            using var stub = StubUdsServer.Start(
                replyFor: req =>
                {
                    // req like "LOOKUP udp 33001" → "OK 10.0.0.1:33001\n"
                    var parts = req.Split(' ');
                    var port = int.Parse(parts[2]);
                    return $"OK 10.0.0.{port - 33000}:{port}\n";
                });

            var results = new IPEndPoint?[10];
            // CI thread-pool contention can exceed the production 200ms
            // ReceiveTimeout under 10-way Parallel.For load; this test
            // asserts correctness (no cross-contamination), not timeout
            // shape — so pass a generous timeout. LookupViaSocket_SocketTimeout_Throws
            // still verifies the production default fires within 2000ms.
            Parallel.For(0, 10, i =>
            {
                results[i] = Ss14WrapperRemoteAddressOverride.LookupViaSocket(
                    stub.Path, "udp", 33001 + i, timeoutMs: 5000);
            });

            Assert.Multiple(() =>
            {
                var seen = new HashSet<string>();
                for (var i = 0; i < 10; i++)
                {
                    Assert.That(results[i], Is.Not.Null, $"[{i}] must parse");
                    Assert.That(results[i]!.Port, Is.EqualTo(33001 + i));
                    seen.Add(results[i]!.ToString());
                }
                Assert.That(seen.Count, Is.EqualTo(10),
                    "all 10 endpoints must be distinct — no cross-contamination");
            });
        }

        /// <summary>TC: Lookup_RequestWireFormat_MatchesSpec
        /// — the stub records the exact bytes; we assert byte-for-byte
        /// match against the spec wire format. Case-sensitive, LF not CRLF,
        /// single space separator.</summary>
        [Test]
        public void LookupViaSocket_RequestWireFormat_MatchesSpec()
        {
            string? recorded = null;
            using var stub = StubUdsServer.Start(
                replyFor: req => "MISS\n",
                recordRequest: req => recorded = req);

            Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "udp", 33000);

            // Spec wire format (per ss14-patch-tests.md and wrapper api.go).
            // Note: recorded omits the trailing "\n" because StubUdsServer
            // splits on it; we verify the LF separator below.
            Assert.That(recorded, Is.EqualTo("LOOKUP udp 33000"),
                "wire format MUST be exactly 'LOOKUP udp 33000' (lowercase proto, single space, no extras)");
        }

        /// <summary>TC: Lookup_RequestWireFormat raw bytes — assert that
        /// the request ends with LF (0x0a), not CRLF, and is ASCII.</summary>
        [Test]
        public void LookupViaSocket_RequestRawBytes_AreLfTerminatedAscii()
        {
            byte[]? raw = null;
            using var stub = StubUdsServer.Start(
                replyFor: _ => "MISS\n",
                recordRawBytes: bytes => raw = bytes);

            Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "tcp", 8080);

            Assert.That(raw, Is.Not.Null);
            Assert.That(raw, Is.EqualTo(Encoding.ASCII.GetBytes("LOOKUP tcp 8080\n")));
        }

        /// <summary>TC: Lookup_TcpProtocolBranch
        /// — passing "tcp" as protocol produces the wrapper's tcp-branch reply.</summary>
        [Test]
        public void LookupViaSocket_TcpProtocolBranch()
        {
            using var stub = StubUdsServer.Start(
                replyFor: req => req.Contains(" tcp ")
                    ? "OK 10.0.0.99:80\n"
                    : "OK 10.0.0.1:33000\n");

            var ep = Ss14WrapperRemoteAddressOverride.LookupViaSocket(stub.Path, "tcp", 8080);

            Assert.That(ep!.Address.ToString(), Is.EqualTo("10.0.0.99"));
            Assert.That(ep.Port, Is.EqualTo(80));
        }

        // -- Stub UDS server ------------------------------------------------

        /// <summary>
        ///     In-process UDS server that accepts a single LOOKUP request,
        ///     records it, replies with the canned response from
        ///     <c>replyFor</c>, and exits. Per-test instances live under
        ///     <see cref="Path.GetTempPath"/> with a GUID suffix.
        /// </summary>
        private sealed class StubUdsServer : IDisposable
        {
            public string Path { get; }
            private readonly Socket _listener;
            private readonly CancellationTokenSource _cts = new();
            private readonly Task _serveLoop;

            private StubUdsServer(string path, Func<string, string?> replyFor,
                Action<string>? recordRequest, Action<byte[]>? recordRawBytes,
                int holdConnectionMs)
            {
                Path = path;
                _listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                _listener.Bind(new UnixDomainSocketEndPoint(path));
                _listener.Listen(8);

                _serveLoop = Task.Run(() => ServeLoop(replyFor, recordRequest, recordRawBytes, holdConnectionMs, _cts.Token));
            }

            public static StubUdsServer Start(
                Func<string, string?> replyFor,
                Action<string>? recordRequest = null,
                Action<byte[]>? recordRawBytes = null,
                int holdConnectionMs = 0)
            {
                var path = System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(),
                    $"ss14-test-{Guid.NewGuid():N}.sock");

                if (path.Length > 104)
                {
                    Assert.Ignore(
                        $"UDS path {path.Length} bytes exceeds macOS 104-byte limit; " +
                        "TMPDIR is too long for this test");
                }

                return new StubUdsServer(path, replyFor, recordRequest, recordRawBytes, holdConnectionMs);
            }

            private async Task ServeLoop(Func<string, string?> replyFor,
                Action<string>? recordRequest, Action<byte[]>? recordRawBytes,
                int holdConnectionMs, CancellationToken ct)
            {
                while (!ct.IsCancellationRequested)
                {
                    Socket client;
                    try
                    {
                        client = await _listener.AcceptAsync(ct);
                    }
                    catch (OperationCanceledException) { break; }
                    catch (ObjectDisposedException) { break; }

                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            using (client)
                            {
                                var buf = new byte[1024];
                                var n = await client.ReceiveAsync(buf.AsMemory(), ct);
                                if (n <= 0) return;

                                var raw = new byte[n];
                                Array.Copy(buf, raw, n);
                                recordRawBytes?.Invoke(raw);

                                var req = Encoding.ASCII.GetString(buf, 0, n).TrimEnd('\r', '\n');
                                recordRequest?.Invoke(req);

                                if (holdConnectionMs > 0)
                                    await Task.Delay(holdConnectionMs, ct);

                                var reply = replyFor(req);
                                if (reply == null) return; // null = never reply (timeout test)

                                await client.SendAsync(Encoding.ASCII.GetBytes(reply).AsMemory(), ct);
                            }
                        }
                        catch { /* test-side socket errors are expected on timeout */ }
                    }, ct);
                }
            }

            public void Dispose()
            {
                try { _cts.Cancel(); } catch { }
                try { _listener.Close(); } catch { }
                try { _serveLoop.Wait(TimeSpan.FromSeconds(1)); } catch { }
                try { File.Delete(Path); } catch { }
                _cts.Dispose();
            }
        }
    }
}
