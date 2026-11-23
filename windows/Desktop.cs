using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace IRemote
{
    internal sealed class Desktop : IDisposable
    {
        private readonly Rectangle bounds;
        private readonly Bitmap canvas;
        private readonly Graphics graphics;
        private readonly MemoryStream jpeg = new MemoryStream(128 * 1024);
        private readonly ImageCodecInfo codec;
        private readonly EncoderParameters encoding = new EncoderParameters(1);

        public Desktop()
        {
            bounds = Screen.PrimaryScreen.Bounds;
            double scale = Math.Min(1, Math.Min(1024.0 / bounds.Width, 768.0 / bounds.Height));
            canvas = new Bitmap(Math.Max(1, (int)(bounds.Width * scale)), Math.Max(1, (int)(bounds.Height * scale)), PixelFormat.Format24bppRgb);
            graphics = Graphics.FromImage(canvas);
            codec = Array.Find(ImageCodecInfo.GetImageEncoders(), item => item.FormatID == ImageFormat.Jpeg.Guid);
            encoding.Param[0] = new EncoderParameter(Encoder.Quality, 57L);
        }

        public byte[] Capture()
        {
            IntPtr source = GetDC(IntPtr.Zero);
            if (source == IntPtr.Zero) throw new IOException("No se pudo leer el escritorio.");
            try
            {
                IntPtr target = graphics.GetHdc();
                try
                {
                    SetStretchBltMode(target, 3); // COLORONCOLOR
                    if (!StretchBlt(target, 0, 0, canvas.Width, canvas.Height, source,
                        bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x40CC0020))
                        throw new IOException("El escritorio activo no está disponible.");
                    var cursor = new CursorInfo { Size = Marshal.SizeOf(typeof(CursorInfo)) };
                    if (GetCursorInfo(ref cursor) && (cursor.Flags & 1) != 0 &&
                        bounds.Contains(cursor.Position.X, cursor.Position.Y))
                        DrawIconEx(target, (cursor.Position.X - bounds.X) * canvas.Width / bounds.Width,
                            (cursor.Position.Y - bounds.Y) * canvas.Height / bounds.Height,
                            cursor.Handle, 16, 16, 0, IntPtr.Zero, 3);
                }
                finally { graphics.ReleaseHdc(target); }
            }
            finally { ReleaseDC(IntPtr.Zero, source); }

            jpeg.SetLength(0);
            canvas.Save(jpeg, codec, encoding);
            return jpeg.ToArray();
        }

        public void Position(ushort x, ushort y)
        {
            SetCursorPos(bounds.X + (int)((long)x * (bounds.Width - 1) / 65535),
                bounds.Y + (int)((long)y * (bounds.Height - 1) / 65535));
        }

        public void Dispose()
        {
            graphics.Dispose();
            canvas.Dispose();
            jpeg.Dispose();
            encoding.Dispose();
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PointNative { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct CursorInfo { public int Size, Flags; public IntPtr Handle; public PointNative Position; }

        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
        [DllImport("user32.dll")] private static extern bool GetCursorInfo(ref CursorInfo info);
        [DllImport("user32.dll")] private static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int w, int h, uint step, IntPtr brush, uint flags);
        [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
        [DllImport("gdi32.dll")] private static extern int SetStretchBltMode(IntPtr dc, int mode);
        [DllImport("gdi32.dll")] private static extern bool StretchBlt(IntPtr target, int x, int y, int w, int h, IntPtr source, int sx, int sy, int sw, int sh, uint operation);
    }
}
