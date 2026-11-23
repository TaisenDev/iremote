using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Windows.Forms;
using Microsoft.Win32;

namespace IRemote
{
    internal sealed class ReceiverWindow : Form
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private readonly Label status = new Label { AutoSize = true };
        private readonly Button pair = new Button { Text = "Mostrar QR", AutoSize = true, Enabled = false };
        private readonly CheckBox autoStart = new CheckBox { Text = "Iniciar al entrar en Windows", AutoSize = true };
        private readonly ToolStripMenuItem availability = new ToolStripMenuItem();
        private readonly NotifyIcon tray;
        private readonly Timer timer = new Timer { Interval = 500 };
        private readonly Identity identity;
        private Receiver receiver;
        private LanDiscovery discovery;
        private PairingDialog pairing;
        private bool enabled = true;
        private bool locked;
        private bool exiting;
        private string error;

        public ReceiverWindow(Identity identity)
        {
            this.identity = identity;
            Text = "iremote";
            var brandIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Icon = brandIcon;
            StartPosition = FormStartPosition.CenterScreen;
            Font = SystemFonts.MessageBoxFont;
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(360, 228);
            MinimumSize = new Size(350, 230);

            var content = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
                WrapContents = false, Padding = new Padding(16), AutoScroll = true
            };
            Controls.Add(content);
            var revoke = new Button { Text = "Revocar iPad", AutoSize = true };
            content.Controls.Add(new Label { Text = "Acceso desde el iPad", Font = new Font(Font.FontFamily, 16), AutoSize = true });
            content.Controls.Add(status);
            content.Controls.Add(pair);
            content.Controls.Add(autoStart);
            content.Controls.Add(revoke);
            var hide = new Button { Text = "Ocultar en la bandeja", AutoSize = true };
            content.Controls.Add(hide);

            var actions = new ContextMenuStrip();
            actions.Items.Add("Abrir iremote", null, delegate { ShowSettings(); });
            availability.Click += delegate
            {
                enabled = !enabled;
                if (enabled) StartReceiver(); else StopReceiver();
                RefreshStatus();
            };
            actions.Items.Add(availability);
            actions.Items.Add("Salir del receptor", null, delegate { exiting = true; Close(); });
            tray = new NotifyIcon { Icon = brandIcon, Visible = true, ContextMenuStrip = actions, Text = "iremote" };
            tray.DoubleClick += delegate { ShowSettings(); };

            pair.Click += delegate { ShowPairing(); };
            revoke.Click += delegate
            {
                StopReceiver();
                try { identity.Revoke(); }
                catch (Exception failure) { MessageBox.Show(this, failure.Message, "iremote"); }
                if (enabled) StartReceiver();
            };
            hide.Click += delegate { Hide(); };
            using (var entry = Registry.CurrentUser.OpenSubKey(RunKey))
                autoStart.Checked = entry != null && entry.GetValue("iRemote") != null;
            autoStart.CheckedChanged += delegate { ConfigureStartup(); };
            timer.Tick += delegate { RefreshStatus(); };
            VisibleChanged += delegate { if (Visible) { RefreshStatus(); timer.Start(); } else timer.Stop(); };
            FormClosing += delegate(object sender, FormClosingEventArgs args)
            {
                if (!exiting && args.CloseReason == CloseReason.UserClosing) { args.Cancel = true; Hide(); }
            };
            SystemEvents.SessionSwitch += SessionSwitch;
            FormClosed += delegate
            {
                SystemEvents.SessionSwitch -= SessionSwitch;
                timer.Dispose();
                StopReceiver();
                tray.Dispose();
                actions.Dispose();
                brandIcon.Dispose();
            };
            var handle = Handle;
            StartReceiver();
        }

        public void ShowSettings()
        {
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Show();
            Activate();
        }

        private void ConfigureStartup()
        {
            try
            {
                using (var entry = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (autoStart.Checked)
                        entry.SetValue("iRemote", "\"" + Application.ExecutablePath + "\" " + identity.Certificate.Thumbprint + " --background");
                    else entry.DeleteValue("iRemote", false);
                }
            }
            catch (Exception failure)
            {
                MessageBox.Show(this, failure.Message, "No se pudo cambiar el inicio automático");
            }
        }

        private void ShowPairing()
        {
            var address = LanAddress.List().FirstOrDefault();
            if (receiver == null || address == null) return;
            using (pairing = new PairingDialog(identity, address))
            {
                pairing.Icon = Icon;
                pairing.ShowDialog(this);
            }
            pairing = null;
        }

        private void StartReceiver()
        {
            if (locked || receiver != null) return;
            error = null;
            try
            {
                receiver = new Receiver(identity, null, LanDiscovery.Port);
                discovery = new LanDiscovery(identity.Fingerprint);
            }
            catch (SocketException failure)
            {
                StopReceiver();
                error = "No se pudo iniciar: " + failure.SocketErrorCode;
                enabled = false;
            }
            RefreshStatus();
        }

        private void StopReceiver()
        {
            if (pairing != null && !pairing.IsDisposed) pairing.Close();
            identity.ClosePairing();
            if (discovery != null) { discovery.Dispose(); discovery = null; }
            if (receiver != null) { receiver.Dispose(); receiver = null; }
            RefreshStatus();
        }

        private void RefreshStatus()
        {
            pair.Enabled = receiver != null && LanAddress.List().Length > 0;
            status.Text = locked ? "Pausado mientras Windows está bloqueado" :
                error ?? (receiver == null ? "Acceso pausado" : pair.Enabled ? receiver.Status : "Sin red IPv4 privada");
            availability.Text = enabled ? "Pausar acceso" : "Habilitar acceso";
            tray.Text = receiver != null ? "iremote · Disponible en LAN" : "iremote · En pausa";
        }

        private void SessionSwitch(object sender, SessionSwitchEventArgs args)
        {
            if (args.Reason != SessionSwitchReason.SessionLock && args.Reason != SessionSwitchReason.SessionUnlock &&
                args.Reason != SessionSwitchReason.SessionLogoff) return;
            if (IsDisposed || !IsHandleCreated) return;
            BeginInvoke(new Action(delegate
            {
                locked = args.Reason != SessionSwitchReason.SessionUnlock;
                if (locked) StopReceiver();
                else if (enabled) StartReceiver();
                RefreshStatus();
            }));
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
            bool background = args.Length == 2 && args[1] == "--background";
            try
            {
                if (args.Length != 1 && !background) throw new ArgumentException("Inicia iremote con Start-iRemote.ps1.");
                using (var mutex = new System.Threading.Mutex(false, "Local\\iRemote.Receiver"))
                {
                    if (!mutex.WaitOne(0)) throw new InvalidOperationException("El receptor está activo en la bandeja de Windows.");
                    try
                    {
                        var identity = new Identity(args[0], Path.Combine(
                            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iRemote"));
                        using (var window = new ReceiverWindow(identity))
                        using (var context = new ApplicationContext())
                        {
                            window.FormClosed += delegate { context.ExitThread(); };
                            if (!background) window.ShowSettings();
                            Application.Run(context);
                        }
                    }
                    finally { mutex.ReleaseMutex(); }
                }
            }
            catch (Exception error)
            {
                if (!background) MessageBox.Show(error.Message, "iremote", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
