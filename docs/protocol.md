# Protocolo de iremote

El iPad es el cliente TCP. Se establece TLS 1.2 antes de transmitir cualquier mensaje. El certificado de Windows se verifica contra los primeros 12 bytes de SHA-256 de su DER, introducidos localmente durante la configuración. No se instala el certificado como autoridad de confianza.

Los mensajes se componen de un byte de tipo, cuatro bytes de longitud en orden de red y el cuerpo. El receptor procesa una sesión a la vez. El lector rechaza comandos que superen 8192 bytes y valida la longitud de cada comando. Las solicitudes de imagen tienen una única respuesta. Los mensajes de entrada no requieren respuesta.

## Vinculación y descubrimiento

Windows muestra localmente un QR con la dirección de respaldo, el puerto, la huella y un código temporal. El iPad conserva la huella y el secreto tras el primer emparejamiento. Para localizar esa identidad después, envía `IRLAN1` y 12 bytes aleatorios por UDP a los puertos 28251–28255 de la subred. Windows escucha en el primer puerto libre en ambos protocolos y devuelve los 18 bytes, dos bytes del puerto TCP y la huella de 12 bytes. El iPad usa la IP que originó la respuesta, vuelve a validar la huella dentro de TLS y solo entonces transmite la credencial. El anuncio por UDP no concede acceso.

| Tipo | Dirección | Cuerpo |
| --- | --- | --- |
| 1 Resume | iPad → PC | Secreto de 32 bytes |
| 2 Pair | iPad → PC | Código ASCII de 10 dígitos |
| 3 Frame | iPad → PC | Vacío |
| 4 Pointer | iPad → PC | X e Y normalizadas como uint16, luego acción 0 mover, 1 bajar izquierdo, 2 soltar izquierdo, 3 bajar derecho, 4 soltar derecho |
| 5 Scroll | iPad → PC | Dos int16, delta vertical y horizontal |
| 6 Text | iPad → PC | UTF-8, hasta 4096 bytes |
| 7 Key | iPad → PC | Código de tecla virtual Windows, luego máscara Ctrl/Alt/Shift/Win en los bits 0 a 3 |
| 64 Ready | PC → iPad | Vacío al reanudar, secreto de 32 bytes al emparejar |
| 65 Picture | PC → iPad | JPEG, hasta 1024 × 768 y 1 MiB |
| 66 Refused | PC → iPad | Vacío |
| 67 Still | PC → iPad | Vacío, conserva la última imagen |

La primera operación solo puede ser Resume o Pair. El servidor autentica al cliente antes de capturar la pantalla o aplicar entrada. La conexión se cierra tras un mensaje inválido, un error de TLS o un tiempo de espera. Al salir de una sesión se liberan los botones que el cliente dejó presionados.
