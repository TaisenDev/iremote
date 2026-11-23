using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace IRemote
{
    internal sealed class ReceiverWindow : Form
    {
        private readonly ComboBox network = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 350 };
        private readonly NumericUpDown port = new NumericUpDown { Minimum = 1024, Maximum = 65535, Value = 47921 };
        private readonly Button toggle = new Button { Text = "Iniciar receptor", AutoSize = true };
        private readonly Button pair = new Button { Text = "Generar código", AutoSize = true, Enabled = false };
        private readonly Button revoke = new Button { Text = "Revocar iPad", AutoSize = true };
        private readonly TextBox fingerprint = new TextBox { ReadOnly = true, Width = 350 };
        private readonly TextBox code = new TextBox { ReadOnly = true, Width = 180 };
        private readonly Label status = new Label { AutoSize = true };
        private readonly Label pairing = new Label { AutoSize = true };
        private readonly Timer timer = new Timer { Interval = 500 };
        private readonly Identity identity;
        private Receiver receiver;

        public ReceiverWindow(Identity identity)
        {
            this.identity = identity;
            Text = "iremote · Receptor";
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            var content = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
                WrapContents = false, Padding = new Padding(18), AutoScroll = true };
            Controls.Add(content);
            ClientSize = new Size(410, 370);
            MinimumSize = new Size(400, 370);
            content.Controls.Add(new Label { Text = "Mi PC", Font = new Font(Font.FontFamily, 18), AutoSize = true });
            content.Controls.Add(status);
            content.Controls.Add(new Label { Text = "Dirección de esta PC en la red local", AutoSize = true });
            content.Controls.Add(network);
            content.Controls.Add(new Label { Text = "Puerto", AutoSize = true });
            content.Controls.Add(port);
            content.Controls.Add(toggle);
            content.Controls.Add(new Label { Text = "Huella del receptor", AutoSize = true });
            content.Controls.Add(fingerprint);
            content.Controls.Add(pair);
            content.Controls.Add(code);
            content.Controls.Add(pairing);
            content.Controls.Add(revoke);

            fingerprint.Text = identity.Fingerprint;
            LoadAddresses();
            toggle.Click += delegate { if (receiver == null) StartReceiver(); else StopReceiver(); };
            pair.Click += delegate { code.Text = identity.OpenPairing(); };
            revoke.Click += delegate
            {
                StopReceiver();
                try { identity.Revoke(); RefreshStatus(); }
                catch (Exception error) { MessageBox.Show(this, error.Message, "iremote"); }
            };
            timer.Tick += delegate { RefreshStatus(); };
            timer.Start();
            SystemEvents.SessionSwitch += SessionSwitch;
            FormClosed += delegate
            {
                SystemEvents.SessionSwitch -= SessionSwitch;
                timer.Dispose();
                StopReceiver();
            };
            RefreshStatus();
        }

        private void LoadAddresses()
        {
            network.Items.Clear();
            network.Items.AddRange(LanAddress.List());
            if (network.Items.Count > 0) network.SelectedIndex = 0;
        }

        private void StartReceiver()
        {
            var address = network.SelectedItem as LanAddress;
            if (address == null) { LoadAddresses(); RefreshStatus(); return; }
            try
            {
                receiver = new Receiver(identity, address, (int)port.Value);
                network.Enabled = port.Enabled = false;
                pair.Enabled = true;
                toggle.Text = "Detener receptor";
                RefreshStatus();
            }
            catch (System.Net.Sockets.SocketException error)
            {
                LoadAddresses();
                MessageBox.Show(this, error.Message, "No se pudo abrir el receptor");
            }
        }

        private void StopReceiver()
        {
            if (receiver != null) receiver.Dispose();
            receiver = null;
            network.Enabled = port.Enabled = true;
            pair.Enabled = false;
            toggle.Text = "Iniciar receptor";
            RefreshStatus();
        }

        private void RefreshStatus()
        {
            status.Text = receiver != null ? receiver.Status :
                network.Items.Count > 0 ? "Receptor detenido" : "Conecta la PC a una red IPv4 privada";
            string state = identity.PairingStatus;
            pairing.Text = state;
            if (state == "Emparejamiento cerrado") code.Clear();
        }

        private void SessionSwitch(object sender, SessionSwitchEventArgs args)
        {
            if (args.Reason == SessionSwitchReason.SessionLock || args.Reason == SessionSwitchReason.SessionLogoff)
                if (IsHandleCreated && !IsDisposed) BeginInvoke(new Action(StopReceiver));
        }
    }

    internal static class Program
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            SetProcessDPIAware();
            try
            {
                if (args.Length != 1) throw new ArgumentException("Inicia iremote con Start-iRemote.ps1.");
                using (var mutex = new System.Threading.Mutex(false, "Local\\iRemote.Receiver"))
                {
                    if (!mutex.WaitOne(0)) throw new InvalidOperationException("El receptor ya está abierto.");
                    try
                    {
                        var identity = new Identity(args[0], Path.Combine(
                            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iRemote"));
                        Application.Run(new ReceiverWindow(identity));
                    }
                    finally { mutex.ReleaseMutex(); }
                }
            }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "iremote", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
