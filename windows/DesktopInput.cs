using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace IRemote
{
    internal sealed class DesktopInput : IDisposable
    {
        private const uint KeyUp = 2, Unicode = 4, Extended = 1;
        private readonly HashSet<byte> buttons = new HashSet<byte>();
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);

        public void Pointer(Desktop desktop, byte[] data)
        {
            if (data.Length != 5 || data[4] > 4) throw new InvalidDataException();
            desktop.Position(Wire.Word(data, 0), Wire.Word(data, 2));
            switch (data[4])
            {
                case 1: buttons.Add(1); Mouse(0x0002, 0); break;
                case 2: buttons.Remove(1); Mouse(0x0004, 0); break;
                case 3: buttons.Add(2); Mouse(0x0008, 0); break;
                case 4: buttons.Remove(2); Mouse(0x0010, 0); break;
            }
        }

        public void Scroll(byte[] data)
        {
            if (data.Length != 4) throw new InvalidDataException();
            int vertical = (short)Wire.Word(data, 0);
            int horizontal = (short)Wire.Word(data, 2);
            if (vertical != 0) Mouse(0x0800, vertical);
            if (horizontal != 0) Mouse(0x1000, horizontal);
        }

        public void Text(byte[] data)
        {
            if (data.Length > 4096) throw new InvalidDataException();
            foreach (char unit in StrictUtf8.GetString(data))
            {
                if (unit == '\r' || unit == '\n') Pulse(0x0D, 0);
                else if (unit == '\t') Pulse(0x09, 0);
                else if (!char.IsControl(unit))
                {
                    Keyboard(0, unit, Unicode);
                    Keyboard(0, unit, Unicode | KeyUp);
                }
            }
        }

        public void Key(byte[] data)
        {
            if (data.Length != 2 || data[0] == 0 || data[0] > 0xFE || data[1] > 15)
                throw new InvalidDataException();
            Pulse(data[0], data[1]);
        }

        private static void Pulse(ushort key, byte modifiers)
        {
            ushort[] keys = { 0xA2, 0xA4, 0xA0, 0x5B };
            for (int i = 0; i < keys.Length; i++)
                if ((modifiers & (1 << i)) != 0) Keyboard(keys[i], 0, KeyFlags(keys[i]));
            try
            {
                Keyboard(key, 0, KeyFlags(key));
                Keyboard(key, 0, KeyFlags(key) | KeyUp);
            }
            finally
            {
                for (int i = keys.Length - 1; i >= 0; i--)
                    if ((modifiers & (1 << i)) != 0) Keyboard(keys[i], 0, KeyFlags(keys[i]) | KeyUp);
            }
        }

        private static uint KeyFlags(ushort key)
        {
            return (key >= 0x21 && key <= 0x2E) || key == 0x5B ? Extended : 0;
        }

        private static void Mouse(uint flags, int data)
        {
            Send(new Input { Type = 0, Value = new InputValue { Mouse = new MouseInput { Flags = flags, Data = data } } });
        }

        private static void Keyboard(ushort key, ushort scan, uint flags)
        {
            Send(new Input { Type = 1, Value = new InputValue { Keyboard = new KeyInput { Key = key, Scan = scan, Flags = flags } } });
        }

        private static void Send(Input input)
        {
            SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input)));
        }

        public void Dispose()
        {
            if (buttons.Contains(1)) Mouse(0x0004, 0);
            if (buttons.Contains(2)) Mouse(0x0010, 0);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Input { public uint Type; public InputValue Value; }
        [StructLayout(LayoutKind.Explicit)]
        private struct InputValue
        {
            [FieldOffset(0)] public MouseInput Mouse;
            [FieldOffset(0)] public KeyInput Keyboard;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MouseInput { public int X, Y, Data; public uint Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)]
        private struct KeyInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, Input[] inputs, int size);
    }
}
