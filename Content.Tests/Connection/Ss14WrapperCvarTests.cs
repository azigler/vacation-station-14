#nullable enable
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using Content.Server.Connection;
using Moq;
using NUnit.Framework;
using Robust.Shared;
using Robust.Shared.Configuration;
using Robust.Shared.IoC;
using Robust.Shared.Log;
using Robust.Shared.Network;

namespace Content.Tests.Connection
{
    /// <summary>
    ///     Layer 4 cvar-gating tests for
    ///     <see cref="Ss14WrapperRemoteAddressOverride"/> per
    ///     <c>~/dotfiles/ss14-wrapper/docs/ss14-patch-tests.md</c>
    ///     (rewritten for scrutiny finding F2 / bead vs-q7m).
    ///
    ///     The original tests asserted only that <c>Lookup</c> returned
    ///     null — but a BROKEN gate (one that always opened the UDS and
    ///     swallowed exceptions) would also return null. The acceptance
    ///     criterion in vs-4h1 says "OFF cvar produces ZERO socket I/O";
    ///     the only way to prove that is to STAND UP a real UDS server
    ///     and count accepts.
    ///
    ///     The stub server here is a single-socket UDS listener that
    ///     atomically increments <see cref="StubServer.AcceptCount"/> on
    ///     every successful <c>Accept</c>. With the cvar OFF the impl
    ///     must short-circuit before <c>sock.Connect</c> — so
    ///     <c>AcceptCount</c> stays at 0 even though the server is up
    ///     and reachable. With the cvar ON the impl tries the UDS — the
    ///     stub server's accept fires.
    ///
    ///     This is a GENUINE oracle: a regression that opens the UDS
    ///     when the cvar is OFF (e.g. someone removes the
    ///     <c>if (!_cfg.GetCVar(...)) return null;</c> early-return)
    ///     instantly flips <c>AcceptCount</c> from 0 to ≥1 and the test
    ///     fails.
    /// </summary>
    [TestFixture]
    [TestOf(typeof(Ss14WrapperRemoteAddressOverride))]
    public sealed class Ss14WrapperCvarTests
    {
        /// <summary>TC: WrapperCvar_DefaultFalse_NoSocketIO
        /// — the headline test: cvar=false must produce ZERO socket I/O,
        /// proven by an accept-counting stub UDS server that stays at 0.</summary>
        [Test]
        public void WrapperCvar_DefaultFalse_NoSocketIO()
        {
            using var stub = StubServer.Start();
            var cfg = MockCfg(enabled: false, sockPath: stub.Path);
            var impl = NewImpl(cfg, MockLogMan());

            // Hammer Lookup a few times to give a broken gate the
            // opportunity to leak I/O — a single call could plausibly
            // race with the listen socket setup.
            for (var i = 0; i < 5; i++)
            {
                var result = impl.Lookup("udp", new IPEndPoint(IPAddress.Loopback, 33000));
                Assert.That(result, Is.Null, "cvar=false → Lookup MUST return null");
            }

            // Give any in-flight (broken) connect attempt time to land
            // before we assert. 50ms is generous for a localhost UDS.
            Thread.Sleep(50);

            Assert.That(stub.AcceptCount, Is.EqualTo(0),
                "F2 regression guard: with cvar=false the impl MUST NOT " +
                "open the UDS at all. AcceptCount > 0 means the gate is " +
                "broken (someone removed the early-return at the top of " +
                "Lookup, or the cvar lookup is wired wrong).");
        }

        /// <summary>TC: WrapperCvar_True_AttemptsSocketIO
        /// — cvar=true → the impl tries the UDS at least once. The stub
        /// server accepts then immediately closes, so Lookup returns
        /// null via the empty-reply parse path, but AcceptCount &gt;= 1.</summary>
        [Test]
        public void WrapperCvar_True_AttemptsSocketIO()
        {
            using var stub = StubServer.Start();
            var cfg = MockCfg(enabled: true, sockPath: stub.Path);
            var impl = NewImpl(cfg, MockLogMan());

            var result = impl.Lookup("udp", new IPEndPoint(IPAddress.Loopback, 33000));
            // Result might be null (stub closes without replying) — what
            // matters is that the UDS connection was attempted at all.
            // The point of this test is the AcceptCount assertion below.
            _ = result;

            // Wait briefly for the accept to register on the stub side.
            // The impl's Connect is synchronous so by the time Lookup
            // returns the stub has either accepted or it never will.
            stub.WaitForAccept(TimeSpan.FromSeconds(2));

            Assert.That(stub.AcceptCount, Is.GreaterThanOrEqualTo(1),
                "cvar=true → impl MUST open the UDS at least once");
        }

        /// <summary>TC: WrapperCvar_Hotflip_TogglesIO
        /// — the gate is checked on EVERY Lookup call, not just at
        /// construction. Start cvar=false (AcceptCount=0); flip to true
        /// (AcceptCount goes > 0); flip back to false (AcceptCount
        /// frozen, doesn't go up further).</summary>
        [Test]
        public void WrapperCvar_Hotflip_TogglesIO()
        {
            using var stub = StubServer.Start();

            var cfg = new Mock<IConfigurationManager>();
            var enabled = false;
            cfg.Setup(c => c.GetCVar(CVars.NetUseWrapperRemoteAddress))
                .Returns(() => enabled);
            cfg.Setup(c => c.GetCVar(CVars.NetWrapperSocket))
                .Returns(stub.Path);

            var impl = NewImpl(cfg.Object, MockLogMan());
            var observed = new IPEndPoint(IPAddress.Loopback, 33000);

            // Phase 1: cvar=false → AcceptCount stays at 0.
            for (var i = 0; i < 3; i++)
                _ = impl.Lookup("udp", observed);
            Thread.Sleep(50);
            Assert.That(stub.AcceptCount, Is.EqualTo(0),
                "phase 1 (cvar=false): no UDS I/O");

            // Phase 2: flip cvar=true → AcceptCount climbs.
            enabled = true;
            var before = stub.AcceptCount; // 0
            for (var i = 0; i < 3; i++)
                _ = impl.Lookup("udp", observed);
            stub.WaitForAccept(TimeSpan.FromSeconds(2));
            var afterOn = stub.AcceptCount;
            Assert.That(afterOn, Is.GreaterThan(before),
                "phase 2 (cvar=true): UDS I/O resumes — hot-flip honored");

            // Phase 3: flip cvar=false again → AcceptCount FROZEN.
            enabled = false;
            for (var i = 0; i < 3; i++)
                _ = impl.Lookup("udp", observed);
            Thread.Sleep(50);
            Assert.That(stub.AcceptCount, Is.EqualTo(afterOn),
                "phase 3 (cvar=false again): UDS I/O stops — gate re-closes");
        }

        /// <summary>TC: WrapperCvar_EmptySockPath_ShortCircuits
        /// — defensive: an empty/null socket-path cvar must short-circuit
        /// independently of the enable cvar. Stub server still up but at a
        /// different path; impl should not connect anywhere.</summary>
        [Test]
        public void WrapperCvar_EmptySockPath_ShortCircuits()
        {
            using var stub = StubServer.Start();
            var cfg = MockCfg(enabled: true, sockPath: "");
            var impl = NewImpl(cfg, MockLogMan());

            for (var i = 0; i < 3; i++)
                _ = impl.Lookup("udp", new IPEndPoint(IPAddress.Loopback, 33000));
            Thread.Sleep(50);

            Assert.That(stub.AcceptCount, Is.EqualTo(0),
                "empty sockPath MUST short-circuit — impl must not connect " +
                "to anything (including the stub server, which has a " +
                "different path anyway)");
        }

        // -- Helpers ----------------------------------------------------------

        private static IConfigurationManager MockCfg(bool enabled, string sockPath)
        {
            var cfg = new Mock<IConfigurationManager>();
            cfg.Setup(c => c.GetCVar(CVars.NetUseWrapperRemoteAddress)).Returns(enabled);
            cfg.Setup(c => c.GetCVar(CVars.NetWrapperSocket)).Returns(sockPath);
            return cfg.Object;
        }

        private static ILogManager MockLogMan()
        {
            var sawmill = new Mock<ISawmill>();
            var logMan = new Mock<ILogManager>();
            logMan.Setup(l => l.GetSawmill(It.IsAny<string>())).Returns(sawmill.Object);
            return logMan.Object;
        }

        /// <summary>
        ///     Construct an <see cref="Ss14WrapperRemoteAddressOverride"/>
        ///     with the given mock dependencies injected via reflection
        ///     (the class uses <c>[Dependency]</c> field injection,
        ///     which the test harness simulates here without spinning up
        ///     a full IoC container).
        /// </summary>
        private static Ss14WrapperRemoteAddressOverride NewImpl(
            IConfigurationManager cfg, ILogManager logMan)
        {
            var impl = new Ss14WrapperRemoteAddressOverride();
            InjectField(impl, "_cfg", cfg);
            InjectField(impl, "_logMan", logMan);
            return impl;
        }

        private static void InjectField(object target, string name, object value)
        {
            var f = target.GetType().GetField(name,
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            Assert.That(f, Is.Not.Null, $"field {name} not found on {target.GetType().Name}");
            f!.SetValue(target, value);
        }

        // -- Stub UDS server -------------------------------------------------

        /// <summary>
        ///     Minimal UDS listener that COUNTS accepts and immediately
        ///     closes each client connection. Exists only to prove the
        ///     cvar gate suppresses socket I/O — replies are not the
        ///     point; the accept-count IS the oracle.
        /// </summary>
        private sealed class StubServer : IDisposable
        {
            public string Path { get; }
            private int _acceptCount;
            public int AcceptCount => Volatile.Read(ref _acceptCount);

            private readonly ManualResetEventSlim _accepted = new(false);
            private readonly Socket _listener;
            private readonly CancellationTokenSource _cts = new();
            private readonly Task _serveLoop;

            private StubServer(string path)
            {
                Path = path;
                _listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                _listener.Bind(new UnixDomainSocketEndPoint(path));
                _listener.Listen(8);
                _serveLoop = Task.Run(() => ServeLoop(_cts.Token));
            }

            public static StubServer Start()
            {
                var path = System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(),
                    $"ss14-cvar-{Guid.NewGuid():N}.sock");
                if (path.Length > 104)
                    Assert.Ignore($"UDS path {path.Length} bytes exceeds macOS 104-byte limit");
                return new StubServer(path);
            }

            /// <summary>
            ///     Block until at least one accept has fired or the timeout
            ///     elapses. Used to make assertions deterministic — the
            ///     impl's Socket.Connect is synchronous but the stub's
            ///     AcceptAsync resolves on a worker thread.
            /// </summary>
            public void WaitForAccept(TimeSpan timeout) => _accepted.Wait(timeout);

            private async Task ServeLoop(CancellationToken ct)
            {
                while (!ct.IsCancellationRequested)
                {
                    Socket client;
                    try { client = await _listener.AcceptAsync(ct); }
                    catch (OperationCanceledException) { break; }
                    catch (ObjectDisposedException) { break; }

                    Interlocked.Increment(ref _acceptCount);
                    _accepted.Set();
                    // Close immediately — Lookup will see an empty reply
                    // and return null. The point of this stub is the
                    // accept-count, not the reply behavior.
                    try { client.Close(); } catch { }
                }
            }

            public void Dispose()
            {
                try { _cts.Cancel(); } catch { }
                try { _listener.Close(); } catch { }
                try { _serveLoop.Wait(TimeSpan.FromSeconds(1)); } catch { }
                try { File.Delete(Path); } catch { }
                _cts.Dispose();
                _accepted.Dispose();
            }
        }
    }
}
