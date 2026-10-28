# My Presets en Send A / Send B

Rama: `feat/send-fx-user-presets` (desde `integration/lttte-schwung-v1.7.3-b`).
Continúa [My Presets en Master FX](LTTTE_MASTER_FX_USER_PRESETS.md): mismo
código, ahora para las 8 posiciones de cada bus de envío. Nada de esto se ha
publicado upstream ni se ha probado aún en el Move.

## Qué hace

Igual que en Master FX: cada efecto que tengas en **Send A** o **Send B**
tiene ahora, al final de su rejilla de knobs, la página **My Presets** para
guardar y recuperar tus ajustes de ese efecto (por ejemplo, una reverb
"Sala corta" y "Catedral" en Send A).

- Un preset es la "foto" completa del estado del efecto. Se guarda en
  `/data/UserData/schwung/presets/<id-del-módulo>/<nombre>.json`.
- Los presets son **del módulo, no del sitio**: un preset de una reverb
  guardado en Send A aparece también si cargas esa reverb en Send B, en
  Master FX o en un slot de instrumento (es la misma carpeta).
- El aparato recuerda **qué preset tiene cargado cada posición** de Send A y
  Send B, por set, también tras reiniciar o cambiar de set. Si mueves un
  knob después de cargarlo, aparece un `*` delante del nombre (en la fila
  Preset y en la cabecera, `SNDA > * Nombre`) hasta que guardes o cargues
  otro.

## Cómo se usa en el Move

Requisito: **Param View = Knobs** (Global Settings).

1. Abre los buses de FX y entra en **Send A** (o **Send B**).
2. Selecciona un efecto cargado con el jog y haz **clic**: se abre su rejilla
   de knobs (cabecera `SNDA` / `SNDB`).
3. Gira el jog **más allá de la última página**: aparece **My Presets**. Clic
   para entrar en su menú.
4. Filas (idénticas a Master FX):
   - **Preset** — el preset cargado (`(none)`, `Nombre` o `* Nombre`). Clic =
     lista de tus presets; clic en uno lo **carga** y vuelves a esta página.
   - **Save** — (solo con uno cargado) sobrescribe ese preset con el sonido
     actual.
   - **Save As** — teclado en pantalla para guardarlo con otro nombre (nunca
     sobrescribe; si existe añade " 2", " 3"…).
   - **Delete** — (solo con uno cargado) confirmación No/Sí y borra el archivo.
5. **Back** en la lista o en la confirmación vuelve a My Presets del mismo
   efecto, dentro del mismo Send (al salir, el aviso dice "Send A"/"Send B").

## Qué quedó fuera

- **Sin página "Module"** (Swap/Remove/Add to List/…): igual que Master FX.
  Para cambiar o quitar el efecto, Shift+Click en el diagrama del Send o
  Delete+clic.
- **Sin audición** al moverte por la lista, aunque Audition esté encendido:
  cambiaría el retorno entero del Send mientras navegas, y el autosave de los
  Sends no tiene la protección del de los slots. Solo carga al hacer clic.
- **Inserts de bus** (`bus1:fx…`) siguen sin My Presets.
- **Módulos con interfaz propia** (ui_chain) cargados en un Send: no reciben
  My Presets (solo la rejilla estándar).
- El nombre del preset cargado se escribe con el autosave normal (~5 s); si
  apagas justo después de cargar, puede perderse el nombre (el sonido lo
  guarda el mismo autosave).
- Si otro cliente (Remote UI, una herramienta en overtake) cambia o vacía el
  efecto de una posición, el nombre se borra en el siguiente autosave (no al
  instante).

## Detalle técnico (para revisar el código)

- No se tocó C. El shim ya sirve `send<N>:fx<M>:state` para **leer y
  escribir** igual que `master_fx:fxN:state` (bloque de sends en
  `shadow_chain_mgmt.c`, enrutado por `send_fx_key.h`, con los mismos
  envoltorios de escenas). El flujo de presets usa el **slot IPC 0** con la
  clave con prefijo (`send1:fx2`), igual que Master FX.
- Los helpers de Master FX pasaron a ser **por bus** (`fxBus*` en
  `src/shadow/shadow_ui.js`, índice en `FX_BUSES`: 0 master, 1 Send A, 2
  Send B): `fxBusOfComponentKey`, `fxBusUserPresetPrefix`,
  `fxBusComponentModuleId`, `fxBusPresetFlowOptions`,
  `remapFxBusUserPresetRecords`, `clear/sync…FxBusUserPresetRecord`,
  `fxBusUserPresetField`, `fxBusRecordOrphaned`. Master FX usa los mismos con
  bus 0. `shadow_ui_presets.mjs` no cambió de comportamiento (ya aceptaba un
  destino).
- `componentParamPagesIo` ya no excluye los Sends (los inserts de bus sí).
- Vuelta a la rejilla: `maybeReturnToFxBusComponentGrid` (sustituye al de
  Master FX): solo vuelve si el bus de la clave es el que está en pantalla.
- Registro: `currentUserPresets["0:send1:fxN"]` / `["0:send2:fxN"]` (sin
  choque con `0:master_fx:fxN` ni con `0:fxN` del slot 1). Sigue al chain al
  reordenar/insertar/quitar (`MASTER_CHAIN_TARGET.onReshape` → bus en
  pantalla), se borra al cambiar de módulo en el picker (también con None) y
  cuando el autosave ve que el módulo de esa posición ya no es el del preset
  (el registro guarda en memoria el id del módulo).
- Persistencia: campo `user_preset` en `set_state/<set>/send_fx_<bus>_<i>.json`
  **después de `state`** (el parser C de arranque, `fx_boot_restore_one` +
  `master_fx_saved_state.h`, es el mismo que el de Master FX y toma el primer
  `"state"`). Se relee al cambiar de set (`loadSendFxChainConfigForSet`) y al
  arrancar (`syncSendUserPresetRecordsFromFiles`, justo después de Master FX).

## Pruebas automáticas

- `tests/host/test_send_fx_user_presets.sh` (nuevo; falla sin el cambio):
  flujo de presets con destino Send (slot 0, `send1:fx2:state`, sin foco, sin
  audición, salidas a la vista de buses), helpers por bus (sin choques entre
  buses, remapeo solo del bus en pantalla, sync/clear/campo/huérfano),
  `componentParamPagesIo` para sends, guardado real de `saveSendFxChainConfig`
  (orden `state` → `user_preset`, un preset llamado "state" no confunde al
  parser, huérfanos fuera), recarga por set y al arrancar, reconciliador.
- `tests/host/test_trailing_pages_wiring.sh`: se invirtió la exclusión de los
  Sends (ahora reciben io), y las acciones se prueban también en `send1:fx3`.
- Ajustados a los nombres nuevos: `test_master_fx_user_presets.sh`,
  `test_chain_ui_trailing_pages.sh`, `test_master_fx_save_reads_shim.sh`,
  `test_chain_shape_verbs.sh`, `test_preset_record_from_device.sh`.

## Pruebas pendientes en el Move

Nada de esto se ha probado en el aparato. Con una reverb y un delay en Send A
y Send B:

1. **Round-trip**: reverb en Send A fx1 → mueve knobs → My Presets → Save As
   "Corta" → cambia knobs → Save As "Larga" → Preset → carga "Corta": ¿suena
   igual? ¿la fila dice "Corta" sin `*`? Repite en Send B.
2. **`*`**: tras cargar, gira un knob → ¿aparece `* Corta` en la fila y en la
   cabecera (`SNDA > * Corta`)? Save → ¿desaparece?
3. **Delete**: No → vuelve a My Presets sin borrar; Sí → desaparece de la
   lista y la fila vuelve a `(none)`.
4. **Reinicio**: carga "Larga", espera >5 s, reinicia → ¿suena igual y la
   fila sigue diciendo "Larga" sin `*`?
5. **Cambio de set**: set A con "Corta" en Send A fx1, set B con otra cosa →
   A→B→A: ¿cada set recupera su sonido y su nombre? ¿B no hereda el de A?
6. **Reordenar/quitar**: dos efectos con preset en Send A fx1 y fx2 →
   Shift+jog para moverlos / quitar fx1 (Delete+clic) → ¿cada nombre sigue a
   su efecto?
7. **Swap**: cambia el módulo de una posición con preset (Shift+Click) → la
   fila debe decir `(none)`.
8. **Sin cruces entre buses**: mismo efecto en Master FX fx1, Send A fx1 y
   Send B fx1, cada uno con un preset distinto → ¿cada uno muestra el suyo?
   Reordenar Send A no debe mover los nombres de Master FX ni de Send B.
9. **Foco de slot**: estando en el slot 3, carga un preset en Send B → al
   salir, ¿el Move sigue en el slot 3?
10. **Back**: desde la lista y desde la confirmación → My Presets del mismo
    efecto en el mismo Send; Back desde la rejilla → diagrama del Send.
11. **Audition encendido**: mover el jog por la lista de un Send NO cambia el
    sonido hasta hacer clic.
12. **Retorno**: cargar un preset no debe cambiar el nivel de retorno del Send
    ni el envío A→B (son del bus, no del efecto).
13. **Escenas**: con una escena armada que toque un parámetro del efecto del
    Send, guarda y carga un preset → ¿se guarda el valor del knob (no el de la
    escena) y no hay saltos raros?
