# Port de los mods LTTTE de Schwung v1.3.1 a v1.7.3

CONFIDENTIAL — PROPRIETARY to Jorge A. Uribe R. · 2026-10-21

Rama: `integration/lttte-schwung-v1.7.3` (creada desde la etiqueta oficial `v1.7.3`; `upstream/main` va 13 commits por delante,
`v1.7.3-13-g9dca92b5`, solo catálogo y documentación). La rama anterior `integration/lttte-schwung-v1.3.1` no se tocó y tiene
la etiqueta de rescate `restore/integration-v1.3.1-2026-10-21`. Los commits llevan `(cherry picked from commit …)` con el hash original.

## Qué se portó

Entre v1.3.1 y v1.7.3 hay 329 commits oficiales y 591 archivos cambiados. Ninguno de los mods existía en v1.7.3
(se buscó `knob_step_mode`, `knob_curve`, `knob_step_frac`, `tempo_landmark`, `button_led_owner`, Fine Lock: nada).

| Mod | Resultado | Notas del port |
|---|---|---|
| Modo de paso declarado de perillas (`knob_step_mode`) | **Portado** | Limpio. Más la corrección de precisión de pantalla del Shift fino. |
| Curvas de respuesta (`knob_curve`) | **Portado** | Solo conflicto de documentos (se conservaron ambas secciones). |
| Velocidad de edición (`knob_step_frac`) | **Portado** | Limpio. |
| Referencias musicales de tempo + arreglo de recorte del encabezado | **Adaptado** | `render_page_movy.mjs`: v1.7.3 cambió el recorte del título a "cabeza primero" (`fitHeadTail`). Se mantiene eso y se añadió `fitHeaderRight` (no corta un token a la mitad) sobre el lado derecho. `shadow_ui_param_pages.mjs`: upstream añadió `canvasPageHook` junto a `getTempo`; se conservaron los dos. |
| Refresco del contrato de ley de perilla al cambiar un enum | **Adaptado** | `page_controller.mjs`: upstream centralizó la escritura en `cacheWritten()`, que ya fija el valor y el *settle*; se quitaron esas dos líneas duplicadas. El git unió mal un trozo en `commitValue`; se movió a `commitEnum`, que es donde estaba (lo atrapó `test_knob_law_contract_refresh.sh`). |
| Delete + clic de la rueda quita un dispositivo; Fine Lock (Shift con doble toque) | **Portado** | Cherry-pick limpio. Las pruebas estáticas de Shift pasan. Pero **upstream añadió gestos Shift nuevos** (ver abajo): hay que repasar en el aparato. El arnés de `test_corun_param_pages.mjs` se actualizó (conoce `syncFineLockScope`, `physicalShiftIsHeld`, `hostPhysicalShiftHeld`). |
| Propiedad de LEDs nativos por botón | **Adaptado (el más delicado)** | El cherry-pick se rehízo a mano: v1.7.3 refactorizó `shadow_led_queue.c` (`strip_move_note_leds`, `rec_arm`, anillo de captura con `ui_mode`/`pulses`). El anillo de captura sigue siendo el de upstream, con los campos nuevos *añadidos* (`flags`, `raw0..3`). **`CONTROL_BUFFER_SIZE` pasó de 256 a 512**: v1.7.3 usa 220 bytes de `shadow_control_t`, nuestros campos añaden 36 y daban justo 256, y la prueba de upstream exige margen (`<`). Los campos se *añaden al final*, así que ningún offset existente cambia; `schwung-manager` mapea `min(256, segmento)` y no se ve afectado. Hay que desplegar el shim y `shadow_ui` juntos. |
| Arreglo de conversión de puntero (compilador estricto) | **Portado** | Cherry-pick limpio. |
| `contract-probe/` y `SchwungTempoTester/u6-port-test/` | **No estaban en el repo** | Eran archivos sin versionar del espacio de trabajo antiguo (el inventario los marca como `UNKNOWN_PROVENANCE_PRESERVED`); no hay nada que portar desde `schwung-archive`. |
| `live_params` / `changes_contract` (ventana móvil) | **Descartado a propósito** | Falló en el aparato; sigue archivado en `archive/live-params-moving-window-hardware-failed-2026-08-30`. |
| Corrección de `test_widget_sheet.sh` | **Descartado** | Ya la había hecho upstream (igual desde v1.3.1). |

## Pruebas (macOS, 2026-10-21)

- `make -C tests/host test`: pasa completo (incluye `test_button_led_ownership`, `test_ui_flags_layout`).
- `tests/host/*.sh`: **482 de 485 pasan en el Mac**. Las 3 que fallan (`test_led_restore_defers_not_destroys`,
  `test_manager_shm_offsets`, `test_old_entrypoint_payload_compat`) fallan igual en `v1.7.3` limpio por incompatibilidad
  con el bash 3 de macOS (`mapfile`, sintaxis); **dentro de un contenedor Linux (node:20) las tres pasan**, y también
  `test_button_led_ownership.sh`.
- Las suites `tests/{shadow,store,build}` no se corrieron (upstream dice que tienen fallos viejos y se corren a mano).
- Pruebas del manager en Go: no se tocó ningún archivo Go.
- Compilación cruzada ARM64 (`./scripts/build.sh`, Docker): ver el estado en el informe final; si no hay artefacto,
  no se compiló.

## Lo que cambió en upstream (v1.4–v1.7) y toca a TTT.djto / tunnel / delay

1. **Cómo se sirven los archivos de la interfaz web de un módulo** (no cambió desde v1.3.1, pero es la causa más probable
   de "script failed to load"): `GET /api/remote-ui/module-assets/{id}/{filepath...}` (`schwung-manager/main.go`,
   `handleModuleWebUIAsset`). Reglas: el `id` no puede tener `/`, `\` ni `..`; el `filepath` no puede contener `..` (ni
   siquiera como parte de un nombre); el archivo se busca en `modules/<id>` y en `modules/<subcarpeta>/<id>`; se
   resuelven los *symlinks* y el resultado debe quedar **dentro de la carpeta del módulo**; directorios → 404. Se envía
   `Cache-Control: no-store` y, por la regla global, `X-Content-Type-Options: nosniff` (un script con un tipo MIME que
   no sea JavaScript se bloquea). Si el archivo **no está instalado** en esa carpeta (paquete viejo, instalación a medias,
   módulo con otro `id`), la respuesta es 404 y el navegador lo ve como "script failed to load".
2. **Instalación por renombrado (#474, #607)**: el manager ya no extrae con `tar` sobre la carpeta viva; extrae a un
   directorio temporal en el mismo sistema de archivos y mueve archivo por archivo (`atomic_install.go`). Es una
   **fusión archivo a archivo**: lo que ya estaba en la carpeta del módulo y no viene en el paquete nuevo **se queda**.
   Un `v2-app.js` viejo puede convivir con un `web_ui.html` nuevo (o al revés) si el paquete nuevo no lo sobrescribe.
   Si algo se renombró entre versiones, puede quedar una mezcla.
3. **El iframe del Remote UI**: `sandbox="allow-scripts allow-same-origin"` y la URL lleva `?component=<synth|fx1|…>`
   añadida al final (`customUIUrlFor`). Los scripts relativos (`assets/lttte-v2/v2-app.js`) se resuelven contra
   `/api/remote-ui/module-assets/<id>/web_ui.html`, así que dependen de que el `id` de la URL sea el de la carpeta
   instalada. No hay CSP (Content-Security-Policy) en el manager: solo `X-Frame-Options` (DENY, relajado a SAMEORIGIN
   para estos archivos), `nosniff` y `Referrer-Policy: no-referrer`.
4. **Tiempos del servidor**: `WriteTimeout` 60 s para todo lo que no sea el espejo; un archivo grande por una red lenta
   puede cortarse.
5. **`release.json` multi-módulo (#587)**: la instalación "desde URL de GitHub" ya entiende `modules` (varios módulos
   en un solo `release.json`). Es relevante para tunnel y delay, que publican dos módulos (TUNNEL/TUNNELXTO y
   [WETTT]/[WETTTXTO]).
6. **Catálogo**: `module-catalog.json` ahora tiene `taxonomy`, `channels` (estable/beta) y orden por fecha; la
   detección de actualización ya no ofrece bajadas de versión (#505).
7. **Páginas de parámetros**: `ui_hierarchy` ahora se sirve también para inserciones de FX global de envío (#601);
   el re-plan se omite si el contrato no cambió (#519) y se agrupa a uno por tick (#465); páginas *canvas* con
   `ctx.openTextEntry` / `ctx.openFileInTool` / `page_first`; `viz.extra_keys` llegan al navegador (#517); "a module's
   panel was folded, not missing" (#516: un panel plegado ya no parece ausente).
8. **Sin cambios** en `host_read_file` / `host_write_file` (misma firma en `docs/API.md`) ni en el formato de
   `module.json` que usan los módulos del propietario.
9. **Gestos Shift nuevos en v1.7.3** (ver `Fine Lock`): hay ramas Shift+clic para `BUS_CHAIN`, paso de escenas
   (Shift+Vol) y otros. Las pruebas estáticas los cubren, pero un gesto nuevo que lea Shift "a secas" rompería la
   regla de Fine Lock; se resuelve cambiando a la lectura física, como se hizo para Master FX.
10. **Carga de módulos fuera del callback SPI (#605)**: ya no hay un tirón al elegir un módulo; los módulos que
    dependían de que `init` ocurriera dentro del mismo callback no deberían notar nada, pero conviene escuchar.

## Pendiente de aparato

Igual que en `docs/LTTTE_PENDING_HARDWARE_TESTS.md` (actualizado). Ninguno de estos mods se ha probado en hardware
sobre v1.7.3, y el LED de botones nuevo sigue sin consumidor visible.
