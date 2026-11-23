<img src="docs/media/icon-rounded.svg" width="72" height="72" alt="">

# iremote

Controla una PC con Windows desde un iPad mini con iOS 8 y jailbreak, dentro de tu red local y sin Internet.

<img src="docs/media/flujo.svg" width="680" alt="Mostrar QR en Windows, vincular el iPad y conectar después">

## Inicio rápido

1. Extrae el receptor de [Releases](https://github.com/TaisenDev/iremote/releases) en una carpeta permanente y abre `Start-iRemote.ps1`.
2. Pulsa **Mostrar QR** en Windows y **Escanear QR** en el iPad. Cuando se vinculen, puedes cerrar la ventana de Windows y el receptor seguirá en la bandeja.
3. Para volver a entrar, toca **Conectar**. iremote busca el mismo equipo aunque cambie de IP. **Iniciar al entrar en Windows** es opcional.

Tienes modos **Táctil** y **Trackpad**, clic derecho con dos dedos, scroll, arrastre, teclado y teclas de Windows. El receptor comparte el monitor principal y se pausa cuando Windows se bloquea.

## Acceso y seguridad

Si Windows bloquea la conexión, ejecuta `Enable-PrivateLan.ps1` como administrador. Limita TCP y UDP al perfil **Privado**, a la subred local y al ejecutable. El router no necesita reenvío de puertos. Puedes pausar el acceso o revocar el vínculo desde Windows.

El QR dura dos minutos y sirve una vez. El iPad valida la identidad TLS de la PC y guarda el vínculo en el Llavero. Windows protege la credencial con DPAPI. El descubrimiento no transmite credenciales.

## Compilar

- iPad, con Theos y SDK 16.5 para ARMv7: `bash ios/build.sh`.
- Windows, con .NET Framework 4.8: `powershell.exe -NoProfile -File windows/Build.ps1`.

[Protocolo de conexión](docs/protocol.md) · [QRCoder, licencia MIT](windows/QRCoder.LICENSE.txt)

Creado por [TaisenDev](https://github.com/TaisenDev).
