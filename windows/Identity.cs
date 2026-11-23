using System;
using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace IRemote
{
    internal sealed class Identity
    {
        private readonly string tokenPath;
        private readonly object gate = new object();
        private byte[] token;
        private byte[] code;
        private DateTime expires;
        private int attempts;

        public X509Certificate2 Certificate { get; private set; }
        public string Fingerprint { get; private set; }
        public string PairingStatus
        {
            get
            {
                lock (gate)
                    return code != null && DateTime.UtcNow < expires
                        ? "Código válido hasta " + expires.ToLocalTime().ToString("HH:mm:ss")
                        : "Emparejamiento cerrado";
            }
        }

        public Identity(string thumbprint, string directory)
        {
            using (var store = new X509Store(StoreName.My, StoreLocation.CurrentUser))
            {
                store.Open(OpenFlags.ReadOnly);
                var matches = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
                if (matches.Count != 1 || !matches[0].HasPrivateKey)
                    throw new InvalidOperationException("No se encontró el certificado del receptor.");
                Certificate = matches[0];
            }
            using (var sha = SHA256.Create())
                Fingerprint = BitConverter.ToString(sha.ComputeHash(Certificate.RawData), 0, 12).Replace("-", "");
            Directory.CreateDirectory(directory);
            tokenPath = Path.Combine(directory, "device.bin");
            if (File.Exists(tokenPath))
            {
                token = ProtectedData.Unprotect(File.ReadAllBytes(tokenPath), null, DataProtectionScope.CurrentUser);
                if (token.Length != 32) throw new InvalidDataException("Credencial guardada inválida.");
            }
        }

        public string OpenPairing()
        {
            lock (gate)
            {
                var digits = new StringBuilder(10);
                using (var rng = RandomNumberGenerator.Create())
                {
                    var block = new byte[1];
                    while (digits.Length < 10)
                    {
                        rng.GetBytes(block);
                        if (block[0] < 250) digits.Append((char)('0' + block[0] % 10));
                    }
                }
                code = Encoding.ASCII.GetBytes(digits.ToString());
                expires = DateTime.UtcNow.AddMinutes(2);
                attempts = 0;
                return digits.ToString();
            }
        }

        public byte[] Authenticate(bool pairing, byte[] supplied)
        {
            lock (gate)
            {
                if (!pairing)
                    return Equal(token, supplied) ? new byte[0] : null;

                if (code == null || DateTime.UtcNow >= expires) return null;
                attempts++;
                bool accepted = Equal(code, supplied);
                if (accepted || attempts >= 5) code = null;
                if (!accepted) return null;

                var next = new byte[32];
                using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(next);
                var sealedToken = ProtectedData.Protect(next, null, DataProtectionScope.CurrentUser);
                string pending = tokenPath + ".new";
                File.WriteAllBytes(pending, sealedToken);
                if (File.Exists(tokenPath)) File.Replace(pending, tokenPath, null);
                else File.Move(pending, tokenPath);
                token = next;
                return next;
            }
        }

        public void Revoke()
        {
            lock (gate)
            {
                code = null;
                File.Delete(tokenPath);
                token = null;
            }
        }

        private static bool Equal(byte[] expected, byte[] actual)
        {
            if (expected == null || expected.Length != actual.Length) return false;
            int mismatch = 0;
            for (int i = 0; i < expected.Length; i++) mismatch |= expected[i] ^ actual[i];
            return mismatch == 0;
        }
    }
}
