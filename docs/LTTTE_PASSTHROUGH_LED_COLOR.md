# Color de LED de los botones cedidos en overtake (button_passthrough + suppress_sysex)

Rama: `feat/overtake-passthrough-led-color` (desde `integration/lttte-schwung-v1.7.3`).
Contexto: issue upstream charlesvestal/schwung#341.

## El problema, en corto

DJTTTO es una Tool en overtake total: es dueña de la pantalla y de casi todos los
LEDs. Le pide a Schwung que el Move nativo siga manejando algunos botones
(`capabilities.button_passthrough`): Track 1-4 (CC 40-43), Master (CC 79), Play
(CC 85) y Mute (CC 88). Al pulsarlos, el Move los recibe y hace lo suyo (mutear
una pista, play, etc.).

DJTTTO además activa `shadow_set_overtake_suppress_sysex(1)` para que los colores
nativos de los anillos de los knobs y de los pads no se mezclen con los suyos.
Esos colores RGB viajan por **sysex**. El problema: los botones de Track también
son RGB y su color va por el mismo sysex. Con la supresión activa se cortaba
**todo** el sysex, incluido el color de los botones de Track. Resultado: muteabas
una pista en el Move y su LED de Track no se atenuaba.

Usar co-run no sirve, porque en ese modo el Move recupera la pantalla OLED.

## Qué cambia

Con la supresión de sysex activa, Schwung sigue cortando el sysex de LEDs del
Move **excepto** los comandos de color cuyo botón esté en la lista
`button_passthrough`. Es decir, `button_passthrough` pasa a significar
"la pulsación **y el LED** son del Move" para esos botones.

- Track 1-4: el Move pinta su color (incluido el atenuado al mutear).
- Anillos de knobs (71-78) y pads: siguen cortados, DJTTTO manda.
- Master (79), Play (85), Mute (88): si el Move manda color por sysex para ellos,
  también pasa.

Qué **no** cambia:

- Un módulo sin `button_passthrough` (o con la lista vacía): todo igual que antes.
- Con la supresión apagada: todo igual que antes (el sysex ya pasaba entero).
- La pantalla OLED sigue siendo de la Tool.
- Solo se deja pasar un comando de color **completo y bien formado** (los 6
  paquetes `F0 00 21 1D 01 01 3B <sub> <idx> ... F7`). Si llega partido entre dos
  frames, se corta como antes.

Código: `src/host/shadow_led_queue.c`, función `mark_passthrough_rgb_sysex` y su
uso en `shadow_clear_move_leds_if_overtake` (rama de overtake total, la que ya
aplicaba `overtake_suppress_sysex`).

## Cómo probarlo en el Move

Necesitas Schwung con este parche y DJTTTO con el interruptor **NATIVE LED** en
Utility (activa/desactiva la supresión de sysex de DJTTTO).

1. Abre un set con al menos 2 pistas sonando. Entra en DJTTTO.
2. **NATIVE LED en modo "supresión activa"** (el modo normal de DJTTTO).
3. Mutea la pista 1 desde el Move (Mute + Track 1, o como lo hagas normalmente).
   - Esperado: el LED de **Track 1 se atenúa** y vuelve al desmutear.
   - Esperado: los **anillos de los knobs** y los **pads** siguen mostrando los
     colores de DJTTTO, sin parpadeos ni colores del Move colándose.
4. Repite con Track 2, 3 y 4. Cambia de pista seleccionada: el LED de la pista
   seleccionada debe cambiar como en el Move nativo.
5. Comparación: cambia NATIVE LED para **desactivar** la supresión. Ahora todo el
   color nativo pasa (Track y también anillos/pads del Move). Esto ya era así
   antes del parche; sirve para ver la diferencia.
6. Sin el parche (Schwung anterior) y con supresión activa, el paso 3 falla: el
   LED de Track no se atenúa. Esa es la regresión que arregla esto.

Qué mirar con atención (ver riesgos):

- Los pads que corresponden a las notas **79, 85 y 88** (si la fila de abajo es
  68-75: fila 2 columna 4, fila 3 columna 2 y fila 3 columna 5, contando desde
  abajo a la izquierda). Si alguno de esos tres pads muestra un color del Move en
  vez del de DJTTTO, es la colisión de índices descrita abajo.
- Al **salir** de DJTTTO: que el LED de Track muestre el mute actual y no el de
  antes de entrar.

## Pruebas automáticas

`tests/host/test_overtake_passthrough_sysex.c` (en `make -C tests/host test`):

- supresión + lista [40-43, 79, 85, 88]: el color de Track 1 (idx 40) pasa
  intacto; el del anillo 71 y el del pad 68 se cortan; el CC 40 pasa y el CC 71 no;
- cada botón de la lista pasa; dos comandos seguidos (42, 43) pasan y el
  siguiente no listado (72) se corta;
- sin lista o con lista vacía: se corta todo (igual que antes);
- supresión apagada: el sysex queda intacto (igual que antes);
- comandos partidos entre frames o mal formados (sin F7 al final): se cortan;
- sysex en otro cable que no es 0: intacto (igual que antes).

La prueba falla sin el parche (8 comprobaciones) y pasa con él.

## Riesgos y límites

1. **Colisión de índices pad/botón (no verificado en hardware).** El sysex de
   LED usa un solo índice de 0 a 127. El código existente (co-run) supone que el
   índice es el CC del botón o la nota del pad. Las notas de los pads (68-99)
   comparten número con 79, 85 y 88. Si el Move pinta los pads por sysex con
   índice = nota, esos tres pads dejarían pasar el color nativo. Track 1-4
   (40-43) no tienen ese problema. Si se ve en el Move, la salida rápida es
   quitar 79/85/88 de la lista de passthrough de LED (requeriría separar "LED" de
   "pulsación" en la capacidad) o capturar el tráfico real con el diagnóstico
   `led_capture_on` para saber cómo indexa el Move los pads.
2. **Color al salir de la Tool.** Al salir del overtake, Schwung repinta el color
   sysex que tenía guardado de antes de entrar. Para los botones cedidos eso puede
   ser un color viejo hasta que el Move vuelva a pintar ese LED. Esto ya pasaba
   antes con la supresión apagada; el parche no lo empeora ni lo arregla.
3. **Comandos partidos entre frames** se cortan (igual que en co-run): en ese caso
   raro, el LED se queda con el color anterior hasta la siguiente actualización
   del Move.
4. La Tool no debe pintar ella misma los LEDs de los botones que cede: se pelearía
   con el Move.
5. Los paquetes que pasan ocupan sitio en el buffer de salida de LEDs de ese frame
   (6 paquetes por color), un poco menos de espacio para los LEDs de la Tool en
   ese frame. Lo absorbe la cola de LEDs.

## Verificación hecha sin el Move

- `make -C tests/host retest`: los 72 binarios C pasan, incluido el nuevo.
- `tests/host/*.sh`: 482 pasan; 3 fallan igual en la rama base, por el bash 3.2
  de macOS / herramientas BSD (`mapfile`, sintaxis `case`, offsets en Go), no por
  este cambio.
- `shadow_led_queue.c` compila limpio con `-Wall -Wextra -Werror` (compilador
  nativo de macOS). **No** se compiló el shim ARM64 con Docker/dockcross (el
  daemon de Docker no estaba corriendo), así que falta el build completo y la
  prueba en el Move.
