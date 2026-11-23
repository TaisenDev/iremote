using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using QRCoder;

namespace IRemote
{
    internal sealed class PairingDialog : Form
    {
        public PairingDialog(Identity identity, LanAddress address)
        {
            Text = "Vincular iPad";
            StartPosition = FormStartPosition.CenterParent;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            ClientSize = new Size(330, 365);
            MinimizeBox = MaximizeBox = false;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            ShowInTaskbar = false;
            var guidance = new Label
            {
                Text = "En el iPad, abre iremote y toca Escanear QR.",
                TextAlign = ContentAlignment.MiddleCenter, Bounds = new Rectangle(16, 8, 298, 44)
            };
            var picture = new PictureBox
            {
                SizeMode = PictureBoxSizeMode.CenterImage,
                BackColor = Color.White,
                Bounds = new Rectangle(20, 56, 290, 242)
            };
            var close = new Button { Text = "Cerrar", Bounds = new Rectangle(110, 314, 110, 34), DialogResult = DialogResult.Cancel };
            Controls.AddRange(new Control[] { guidance, picture, close });
            CancelButton = close;

            string code = identity.OpenPairing();
            string payload = string.Join("|", "iremote-pair:1", address.Address.ToString(),
                LanDiscovery.Port.ToString(System.Globalization.CultureInfo.InvariantCulture), identity.Fingerprint, code);
            using (var generator = new QRCodeGenerator())
            using (var data = generator.CreateQrCode(payload, QRCodeGenerator.ECCLevel.Q))
            using (var qr = new PngByteQRCode(data))
            using (var bytes = new MemoryStream(qr.GetGraphic(4)))
            using (var image = Image.FromStream(bytes))
                picture.Image = new Bitmap(image);

            var watch = new Timer { Interval = 750 };
            watch.Tick += delegate { if (!identity.PairingOpen) Close(); };
            Shown += delegate { watch.Start(); };
            FormClosed += delegate
            {
                watch.Dispose();
                identity.ClosePairing();
                if (picture.Image != null) picture.Image.Dispose();
            };
        }
    }
}
