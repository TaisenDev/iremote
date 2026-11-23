using System;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace IRemote
{
    internal sealed class LanDiscovery : IDisposable
    {
        internal const int FirstPort = 28251;
        internal const int LastPort = 28255;
        private static readonly byte[] Prefix = Encoding.ASCII.GetBytes("IRLAN1");
        private readonly UdpClient udp;
        private readonly Thread thread;
        private readonly byte[] identity;
        public int Port { get; private set; }

        public LanDiscovery(string fingerprint, int port)
        {
            Port = port;
            identity = Enumerable.Range(0, 12).Select(i => Convert.ToByte(fingerprint.Substring(i * 2, 2), 16)).ToArray();
            udp = new UdpClient(AddressFamily.InterNetwork);
            udp.ExclusiveAddressUse = true;
            try { udp.Client.Bind(new IPEndPoint(IPAddress.Any, Port)); }
            catch { udp.Close(); throw; }
            thread = new Thread(Run) { IsBackground = true, Name = "iRemote discovery" };
            thread.Start();
        }

        private void Run()
        {
            var rate = Stopwatch.StartNew();
            int replies = 0;
            while (true)
            {
                try
                {
                    var remote = new IPEndPoint(IPAddress.Any, 0);
                    byte[] request = udp.Receive(ref remote);
                    if (request.Length != 18 || !request.Take(Prefix.Length).SequenceEqual(Prefix)) continue;
                    if (rate.ElapsedMilliseconds >= 1000) { rate.Restart(); replies = 0; }
                    if (replies >= 12 || !LanAddress.List().Any(item => item.Contains(remote.Address))) continue;
                    replies++;
                    var response = new byte[32];
                    Buffer.BlockCopy(request, 0, response, 0, request.Length);
                    response[18] = (byte)(Port >> 8);
                    response[19] = (byte)(Port & 255);
                    Buffer.BlockCopy(identity, 0, response, 20, identity.Length);
                    udp.Send(response, response.Length, remote);
                }
                catch (SocketException error)
                {
                    if (error.SocketErrorCode == SocketError.ConnectionReset) continue;
                    return;
                }
                catch (ObjectDisposedException) { return; }
            }
        }

        public void Dispose()
        {
            udp.Close();
            thread.Join();
        }
    }
}
