# iremote

Controla el escritorio de Windows desde un iPad mini con iOS 8. La conexión va directamente de un equipo al otro dentro de la red local y funciona sin Internet. El cliente es nativo para ARMv7 y el receptor de Windows usa .NET Framework y las APIs del sistema.

## Inicio rápido

1. En Windows, abre `Start-iRemote.ps1` desde la carpeta del receptor. Selecciona la dirección Wi-Fi o Ethernet de tu casa e inicia el receptor. Si Windows solicita acceso de red, habilita solo el perfil privado.
2. Instala el paquete `.deb` en el iPad con jailbreak y abre iremote. Introduce la dirección y el puerto que ves en Windows.
3. Pulsa **Generar código** en Windows y copia en el iPad la huella y el código. Puedes volver a conectar sin generar otro código. Si cambia la dirección de la PC, edítala en el iPad para reutilizar el vínculo.

Si el firewall ya bloquea el receptor, crea una regla de entrada para `iRemote.Receiver.exe` y el puerto elegido, restringida al perfil **Privado** y a la subred local. El router no necesita redirección de puertos. Las redes de invitados o con aislamiento de clientes pueden impedir que ambos equipos se vean.

## Controles

| Gesto o control | Acción |
| --- | --- |
| Un toque en modo Táctil | Clic donde tocas |
| Un dedo en modo Trackpad | Mover el puntero de forma relativa |
| Dos dedos al tocar | Clic derecho |
| Dos dedos al deslizar | Desplazamiento vertical u horizontal |
| Tres dedos al tocar | Doble clic |
| Mantener pulsado y mover | Arrastrar |
| Teclado | Escribir texto con el teclado de iOS |
| Teclas | Flechas, navegación, F1–F12, Ctrl, Alt, Shift y Win |

Los modificadores se aplican a la siguiente tecla o atajo. El receptor comparte el monitor principal de la sesión interactiva. Al bloquear Windows se detiene el receptor. Las pantallas protegidas de Windows y las combinaciones reservadas como Ctrl+Alt+Supr quedan a cargo del sistema.

## Seguridad y consumo

El receptor escucha en la dirección IPv4 privada seleccionada y comprueba que el interlocutor pertenezca a la misma subred. El iPad verifica 96 bits de la huella SHA-256 del certificado antes de enviar su credencial por TLS 1.2. El código caduca en dos minutos, se cierra tras cinco intentos fallidos y se usa una sola vez. El vínculo duradero usa un secreto aleatorio de 256 bits en el llavero del iPad y protegido por DPAPI en Windows. Se puede revocar desde el receptor. Emparejar un iPad sustituye el vínculo anterior. La clave privada se genera localmente como no exportable.

Durante una sesión el iPad pide las imágenes una a una. El receptor limita la imagen a 1024 × 768 y envía aproximadamente hasta 10 cuadros por segundo. Si la imagen coincide con la anterior, confirma la solicitud sin reenviar el JPEG. El receptor permanece inactivo mientras espera clientes. La eficiencia, la latencia y el alcance efectivos dependen del equipo y de la red.

## Compilación

- **iPad:** configura `THEOS` con el SDK iOS 16.5 y soporte ARMv7. Ejecuta `bash ios/build.sh`. El paquete para iOS 8 queda en `dist/ios`.
- **Windows:** ejecuta `powershell.exe -NoProfile -File windows/Build.ps1` en Windows de 64 bits con .NET Framework 4.8. La aplicación y su lanzador quedan en `dist/windows`.

El código del iPad separa la sesión TLS, el llavero, la pantalla táctil y el controlador de interfaz. El receptor separa autenticación, protocolo, captura e inyección de entrada. El formato de mensajes está en [docs/protocol.md](docs/protocol.md).
