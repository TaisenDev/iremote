using System;
using System.IO;

namespace IRemote
{
    internal static class Wire
    {
        public const byte Resume = 1, Pair = 2, Frame = 3, Pointer = 4, Scroll = 5, Text = 6, Key = 7;
        public const byte Ready = 64, Picture = 65, Refused = 66, Still = 67;
        public const int MaxCommand = 8192;

        public static byte[] Read(Stream stream, int count)
        {
            var buffer = new byte[count];
            for (int offset = 0; offset < count;)
            {
                int read = stream.Read(buffer, offset, count - offset);
                if (read == 0) throw new EndOfStreamException();
                offset += read;
            }
            return buffer;
        }

        public static int Length(byte[] header)
        {
            return header[1] << 24 | header[2] << 16 | header[3] << 8 | header[4];
        }

        public static void Send(Stream stream, byte type, byte[] data)
        {
            int size = data.Length;
            var header = new[] { type, (byte)(size >> 24), (byte)(size >> 16), (byte)(size >> 8), (byte)size };
            stream.Write(header, 0, header.Length);
            if (size > 0) stream.Write(data, 0, size);
        }

        public static ushort Word(byte[] data, int offset)
        {
            return (ushort)(data[offset] << 8 | data[offset + 1]);
        }
    }
}
