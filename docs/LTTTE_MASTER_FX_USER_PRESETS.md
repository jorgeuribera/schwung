# My Presets en Master FX (v1)

Rama: `feat/master-fx-user-presets` (desde `integration/lttte-schwung-v1.7.3`).
Relacionado: issue upstream charlesvestal/schwung#305 ("User Presets para
componentes Master FX"). Nada de esto se ha publicado upstream.

## Qué hace

Hasta ahora "My Presets" (tus presets guardados de un módulo) existía solo en
los módulos de los 4 slots de instrumento. Ahora **cada una de las 8 posiciones
de Master FX** también tiene su página **My Presets**, para pasar rápido entre
configuraciones que ya guardaste de un efecto (por ejemplo, un TUNNEL "abierto"
y uno "cerrado", o dos ajustes de WETTT).

- Un preset es la "foto" completa del estado del módulo (lo mismo que se
  guarda al apagar). Se guarda en
  `/data/UserData/schwung/presets/<id-del-módulo>/<nombre>.json`.
- Los presets son **del módulo, no de la posición**: un preset de TUNNEL
  guardado en Master FX aparece también si cargas TUNNEL en un slot de
  instrumento, y al revés (es la misma carpeta).
- El aparato recuerda **qué preset tiene cargado cada posición** de Master FX,
  por set, también tras reiniciar o cambiar de set. Si después mueves un knob,
  aparece un `*` delante del nombre (en la fila Preset y en la cabecera) hasta
  que guardes o cargues otro.

## Cómo se usa en el Move

Requisito: **Param View = Knobs** (Global Settings). En modo lista no hay
páginas que recorrer.

1. Abre Master FX (Shift+Vol+Menu, Shift+Menu o mantener Menu) y entra en
   **Master FX**.
2. Selecciona un efecto cargado con el jog y haz **clic**: se abre su rejilla
   de knobs.
3. Gira el jog **más allá de la última página** del módulo: aparece la página
   **My Presets**. Haz clic para entrar en su menú.
4. Filas:
   - **Preset** — muestra el preset cargado (`(none)` si ninguno; `* Nombre`
     si cambió desde que lo cargaste). Clic = abre la lista de tus presets;
     clic en uno lo **carga** y vuelves a esta página.
   - **Save** — (solo si hay uno cargado) sobrescribe ese preset con el
     sonido actual. Se queda en la página y borra el `*`.
   - **Save As** — teclado en pantalla para guardarlo con un nombre nuevo
     (nunca sobrescribe: si el nombre existe, añade " 2", " 3"…).
   - **Delete** — (solo si hay uno cargado) pide confirmación No/Sí y borra
     el archivo de ese preset.
5. **Back** en la lista o en la confirmación vuelve a la página My Presets del
   mismo efecto.

## Qué quedó fuera de v1

- **Sin página "Module"** en Master FX (Swap/Remove/Add to List/Clear
  Automation/Module Help). Para cambiar o quitar el efecto sigue usando
  Shift+Click en el diagrama de Master FX.
- **Sin audición** (oír el preset al moverte por la lista): en Master FX se
  aplicaría a toda la mezcla y el autosave de Master FX no tiene la protección
  que tiene el de los slots. Aquí solo carga al hacer clic, aunque el ajuste
  global "Audition" esté encendido.
- **Send A / Send B**: añadidos después, en la rama
  `feat/send-fx-user-presets` (ver
  [LTTTE_SEND_FX_USER_PRESETS.md](LTTTE_SEND_FX_USER_PRESETS.md)). Los
  **inserts de bus** siguen sin My Presets.
- **Módulos con interfaz propia** (ui_chain) cargados en Master FX: no se les
  añade My Presets en v1 (solo la rejilla estándar del host).
- El **snapshot** (Shift+Copy / Shift+Delete) restaura el sonido pero no el
  nombre del preset cargado; tras restaurarlo puede verse un `*` (es honesto:
  el sonido ya no es exactamente el del preset).
- El nombre del preset cargado se escribe a disco con el autosave normal
  (cada ~5 s); si apagas en el mismo segundo de cargar, puede perderse ese
  nombre (el sonido sí lo guarda el mismo autosave).

## Detalle técnico (para revisar el código)

- Un único helper decide qué páginas recibe cada componente:
  `componentParamPagesIo` (`src/shadow/shadow_ui.js`). Para `master_fx:fxN`
  devuelve un io que llama a las MISMAS `componentTrailingMenus` /
  `runComponentActionFromGrid` que los slots, en el slot IPC 0, con la clave
  prefijada (`master_fx:fx2` es su propio prefijo DSP). (Con
  `feat/send-fx-user-presets` los Sends reciben el mismo io y los helpers de
  abajo pasaron a llamarse `fxBus*`, con el bus como parámetro: Master FX es
  el bus 0.)
- `shadow_ui_presets.mjs` acepta un destino opcional (`opts`): slot IPC,
  vista de vuelta (`VIEWS.MASTER_FX`), sin mover el slot enfocado, sin
  audición. Sin `opts` se comporta exactamente como antes (slots).
- Vuelta a la rejilla: `maybeReturnToMasterComponentGrid` (gemelo de
  `maybeReturnToComponentGrid`; hoy `maybeReturnToFxBusComponentGrid`),
  sondeado en cada tick.
- Registro: `currentUserPresets["0:master_fx:fxN"]`. Sigue al chain cuando se
  reordena/inserta/quita (`MASTER_CHAIN_TARGET.onReshape`), se borra al
  cambiar de módulo, Clear, preset de cadena completo o si otro cliente
  (Remote UI/overtake) cambia el módulo.
- Persistencia: campo `user_preset` en `master_fx_N.json` y en
  `shadow_config.json → master_fx_chain.fxN`, **siempre después de `state`**
  (el parser C de arranque `master_fx_saved_state.h` toma el primer
  `"state"`; hay un test C que lo fija). Se relee al arrancar y al cambiar de
  set. No hizo falta tocar C del shim: `master_fx:fxN:state` ya se leía y
  escribía.

## Pruebas automáticas

- `tests/host/test_master_fx_user_presets.sh` (nuevo): flujo de presets real
  con destino Master FX (slot 0, sin tocar el foco, sin audición, todas las
  salidas a MASTER_FX; los slots siguen igual), remapeo de registros, sync,
  campo persistido, reconciliador, sitios de borrado/recarga.
- `tests/host/test_trailing_pages_wiring.sh`: la exclusión de Master FX se
  invirtió (ahora recibe io; sends y bus inserts siguen en `null`), Master FX
  recibe solo "My Presets", y las acciones de Master FX llegan al flujo
  compartido y rechazan las de la página Module.
- `tests/host/test_master_fx_saved_state.c`: un `user_preset` llamado "state"
  escrito después de `state` no confunde al parser de arranque.
- Ajustados (nuevas dependencias en funciones que levantan):
  `test_chain_ui_trailing_pages.sh`, `test_master_fx_save_reads_shim.sh`,
  `test_chain_shape_verbs.sh`.

## Pruebas físicas pendientes en el Move

Nada de esto se ha probado en el aparato. Lista para hacer con TUNNEL y WETTT
en Master FX:

1. **Round-trip básico**: TUNNEL en Master FX 1 → mueve knobs → My Presets →
   Save As "Abierto" → cambia knobs → Save As "Cerrado" → Preset → carga
   "Abierto": ¿suena igual que cuando lo guardaste? ¿la fila dice "Abierto"
   sin `*`? Repite con WETTT en otra posición.
2. **`*`**: tras cargar, gira un knob → ¿aparece `* Abierto` en la fila y en
   la cabecera (`MFX > * Abierto`) en ~0,5 s? Save → ¿desaparece?
3. **Delete**: Delete → No (vuelve a My Presets, nada borrado) → Delete → Sí
   (desaparece de la lista y la fila vuelve a `(none)`).
4. **Reinicio**: carga "Cerrado", espera >5 s, reinicia el Move → ¿suena igual
   que antes? ¿la fila sigue diciendo "Cerrado" (sin `*`)? Si aparece `*` sin
   tocar nada, el módulo normaliza su estado al recargarlo (anotar módulo).
5. **Cambio de set**: set A con "Abierto" en fx1, set B con otra cosa → cambia
   A→B→A → ¿cada set recupera su sonido y su nombre? ¿B no hereda el nombre
   de A?
6. **Reordenar/quitar**: dos efectos con presets en fx1 y fx2 → Shift+jog
   para moverlos / quitar fx1 → ¿cada nombre sigue a su efecto?
7. **Swap**: cambia el módulo de una posición con preset → la fila debe decir
   `(none)`.
8. **Foco de slot**: estando en el slot 3, abre Master FX y carga un preset →
   al salir, ¿el Move sigue en el track/slot 3 (botones, knobs, overlay)?
9. **LFO / escenas / automatización**: con un LFO de Master FX apuntando a un
   parámetro del efecto, guarda un preset → ¿se guarda el valor base (no el
   modulado)? Carga un preset con una escena armada / durante una
   automatización: ¿el resultado es razonable y no hay saltos raros?
10. **Jog/click y Back**: recorrer páginas hasta My Presets, entrar/salir del
    menú, Back desde la lista y desde la confirmación → siempre de vuelta a My
    Presets del mismo efecto; Back desde la rejilla → diagrama de Master FX.
11. **OLED**: la cabecera dice `MFX > <nombre>`, la lista de presets muestra
    el nombre del módulo, nada se corta raro; el teclado de Save As se ve y se
    cierra bien.
12. **Sends**: en Send A / Send B la rejilla de un efecto NO debe mostrar My
    Presets (en esta rama; con `feat/send-fx-user-presets` SÍ lo muestra, ver
    su guía).
13. **Audition encendido**: con Global Settings → Audition = On, mover el jog
    en la lista de Master FX NO debe cambiar el sonido hasta hacer clic.
