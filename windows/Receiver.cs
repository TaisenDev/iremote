using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Threading;

namespace IRemote
{
    internal sealed class LanAddress
    {
        public IPAddress Address;
        public IPAddress Mask;
        public string Adapter;

        public static LanAddress[] List()
        {
            return (from adapter in NetworkInterface.GetAllNetworkInterfaces()
                    where adapter.OperationalStatus == OperationalStatus.Up
                    from item in adapter.GetIPProperties().UnicastAddresses
                    where PrivateIPv4(item.Address) && item.IPv4Mask != null &&
                          !item.IPv4Mask.Equals(IPAddress.Any)
                    select new LanAddress { Address = item.Address, Mask = item.IPv4Mask, Adapter = adapter.Name }).ToArray();
        }

        public bool Contains(IPAddress peer)
        {
            if (!PrivateIPv4(peer)) return false;
            byte[] address = Address.GetAddressBytes(), remote = peer.GetAddressBytes(), mask = Mask.GetAddressBytes();
            for (int i = 0; i < address.Length; i++)
                if ((address[i] & mask[i]) != (remote[i] & mask[i])) return false;
            return true;
        }

        private static bool PrivateIPv4(IPAddress address)
        {
            if (address.AddressFamily != AddressFamily.InterNetwork) return false;
            byte[] ip = address.GetAddressBytes();
            return ip[0] == 10 || (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) ||
                (ip[0] == 192 && ip[1] == 168);
        }

        public override string ToString() { return Address + " · " + Adapter; }
    }

    internal sealed class Receiver : IDisposable
    {
        private readonly Identity identity;
        private readonly LanAddress network;
        private readonly TcpListener listener;
        private readonly Thread worker;
        private readonly object gate = new object();
        private TcpClient peer;
        private bool stopped;
        private volatile string status = "Esperando al iPad";

        public string Status { get { return status; } }

        public Receiver(Identity identity, LanAddress network, int port)
        {
            this.identity = identity;
            this.network = network;
            listener = new TcpListener(network == null ? IPAddress.Any : network.Address, port);
            listener.ExclusiveAddressUse = true;
            listener.Start(2);
            worker = new Thread(Listen) { IsBackground = true, Name = "iRemote LAN" };
            worker.Start();
        }

        private void Listen()
        {
            while (true)
            {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); }
                catch (SocketException) { return; }
                catch (ObjectDisposedException) { return; }

                using (client)
                {
                    lock (gate)
                    {
                        if (stopped) return;
                        var local = ((IPEndPoint)client.Client.LocalEndPoint).Address;
                        var remote = ((IPEndPoint)client.Client.RemoteEndPoint).Address;
                        if (network != null ? !network.Contains(remote)
                            : !LanAddress.List().Any(item => item.Address.Equals(local) && item.Contains(remote))) continue;
                        peer = client;
                    }
                    try { Serve(client); }
                    catch (Exception error)
                    {
                        if (!(error is IOException || error is AuthenticationException ||
                              error is SocketException || error is ObjectDisposedException ||
                              error is InvalidOperationException || error is ArgumentException ||
                              error is System.Security.Cryptography.CryptographicException))
                            throw;
                    }
                    finally
                    {
                        lock (gate) peer = null;
                        status = "Esperando al iPad";
                    }
                }
            }
        }

        private void Serve(TcpClient client)
        {
            client.NoDelay = true;
            client.ReceiveTimeout = 5000;
            client.SendTimeout = 5000;
            using (var tls = new SslStream(client.GetStream()))
            using (var deadline = new Timer(_ => client.Close(), null, 6500, Timeout.Infinite))
            {
                tls.AuthenticateAsServer(identity.Certificate, false, SslProtocols.Tls12, false);
                byte[] header = Wire.Read(tls, 5);
                int length = Wire.Length(header);
                bool pair = header[0] == Wire.Pair && length == 10;
                bool resume = header[0] == Wire.Resume && length == 32;
                if (!pair && !resume) return;
                byte[] reply = identity.Authenticate(pair, Wire.Read(tls, length));
                if (reply == null)
                {
                    Wire.Send(tls, Wire.Refused, new byte[0]);
                    return;
                }

                Wire.Send(tls, Wire.Ready, reply);
                status = "iPad conectado · pantalla compartida";
                using (var desktop = new Desktop())
                using (var input = new DesktopInput())
                {
                    var frameClock = Stopwatch.StartNew();
                    byte[] previous = null;
                    while (true)
                    {
                        deadline.Change(6500, Timeout.Infinite);
                        header = Wire.Read(tls, 5);
                        length = Wire.Length(header);
                        if (length < 0 || length > Wire.MaxCommand) return;
                        byte[] data = Wire.Read(tls, length);
                        switch (header[0])
                        {
                            case Wire.Frame:
                                if (length != 0) return;
                                int wait = 95 - (int)frameClock.ElapsedMilliseconds;
                                if (wait > 0) Thread.Sleep(wait);
                                frameClock.Restart();
                                byte[] image = desktop.Capture();
                                bool changed = previous == null || !previous.SequenceEqual(image);
                                Wire.Send(tls, changed ? Wire.Picture : Wire.Still, changed ? image : new byte[0]);
                                previous = image;
                                break;
                            case Wire.Pointer: input.Pointer(desktop, data); break;
                            case Wire.Scroll: input.Scroll(data); break;
                            case Wire.Text: input.Text(data); break;
                            case Wire.Key: input.Key(data); break;
                            default: return;
                        }
                    }
                }
            }
        }

        public void Dispose()
        {
            lock (gate)
            {
                stopped = true;
                listener.Stop();
                if (peer != null) peer.Close();
            }
            worker.Join();
        }
    }
}
