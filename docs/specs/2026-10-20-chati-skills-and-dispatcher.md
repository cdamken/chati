# chati: un solo comando, skills en bash y `chati doctor`

Fecha: 20.10.2026
Estado: propuesta (para revision de Carlos antes de construir)
Origen: comparacion con OpenClaw + aportes de la sesion "Dot".

## Objetivo

Hoy hay varios puntos de arranque: `chati`, `ailocal start webui|searxng`, `docr`,
`setup.sh`. Queremos un solo comando `chati` como fachada, un mecanismo uniforme
de "skills" en bash, y un `chati doctor` que diga el estado del sistema de un
vistazo. Todo sigue la filosofia de chati: bash puro, local, AI-local (Ollama),
REPL simple, cero runtime, cero marketplace, cero proveedores externos.

Lo que NO hacemos (descartado con Carlos): gateway/daemon, TUI de pantalla
completa, canales (Slack/WhatsApp), multi-agente, proveedores externos ni un
registro remoto de skills. OpenClaw tuvo 341 skills maliciosos de 2857 en su
marketplace; evitamos esa clase de riesgo de raiz manteniendo todo local.

## A. Dispatcher estilo git (consolidar `ailocal` y amigos)

- `chati` sin args = el REPL de siempre (sin cambios para el usuario).
- `chati <sub> [args]` resuelve `libexec/chati-<sub>` y hace `exec`. El dispatcher
  son ~30 lineas: resolver dir, listar `libexec`, exec. Cero logica de negocio.
- Subcomandos iniciales: `chati webui`, `chati search`, `chati doctor`, `chati docr`.
- Los scripts actuales NO se mueven de golpe. Se crean `chati-<sub>` como wrappers
  de una linea hacia los scripts existentes. Los entry points viejos
  (`ailocal start webui`, `setup.sh`) se vuelven shims que imprimen
  "deprecado: usa chati webui" y delegan. Nadie pierde un path; los shims se
  retiran cuando lleven ~1 mes sin uso.
- Lo compartido vive en UN archivo sourceable `chati-common.sh` (rutas, config,
  logging, ping a Ollama). Cada `chati-<sub>` lo hace `source`. Asi cada
  subcomando es un script chico e independiente que solo comparte la lib; no hay
  monolito.
- Contrato de subcomando = igual que el de skill (abajo): cabecera con `summary`
  (para `chati help`) y `--check` obligatorio.

## B. Contrato de skill (ligero, de primera parte, pocos y curados)

Principio rector (Carlos): no queremos mil skills. Pocos, los que de verdad
valgan, que vengan CON chati y se revisen en PR como cualquier otro codigo. Entre
menos, mas seguro y estable. Nada de marketplace ni de instalar codigo de
terceros. Eso borra de un plumazo casi toda la maquinaria de seguridad: como los
skills son codigo propio del repo (igual de confiable que el resto de chati), no
hacen falta `chati skill add`, candado sha256, tamper-check ni `env -i` con
allowlist. Esos existian solo para contener codigo ajeno, que aqui no habra.

1. Ubicacion: `skills/<nombre>/skill.sh` DENTRO del repo (vienen con chati).
   Un directorio por skill para llevar README/prompts/assets. Opcional y de baja
   prioridad: `~/.chati/skills/<nombre>/` para que un usuario avanzado meta el
   suyo; es su propio codigo en su propia maquina (misma confianza que su shell),
   asi que basta una revision de permisos (no escribible por grupo/otros, no
   symlink fuera de la raiz). Sin tercera raiz, sin red, sin auto-install.
2. Metadatos = cabecera de comentarios, parseable con `grep`, sin ejecutar el
   script para descubrirlo:
   ```
   # chati-skill: 1
   # name: docr
   # slash: /docr
   # summary: OCR de un archivo y lo mete al contexto
   # args: <archivo> [idioma]
   # needs: tesseract ollama
   ```
   Listar, `/help` y autocomplete leen SOLO la cabecera.
3. Interfaz:
   - argumentos por argv; contexto por env con prefijo (`CHATI_MODEL`,
     `CHATI_PERSONA`, `CHATI_SESSION_DIR`, `CHATI_CWD`); stdin solo si viene piped;
     stdout = texto que ve el usuario.
   - Para "hablar" con el REPL sin `eval`, un mini-protocolo de lineas con prefijo:
     `@chati:inject <texto>` (meter al contexto del modelo), `@chati:set persona=x`,
     `@chati:say <texto>`. Todo lo demas es texto plano.
   - Exit codes: 0 ok, 2 uso incorrecto, 3 dependencia faltante.
   - `--check` obligatorio: valida `needs` y devuelve 0/3 con una linea de estado,
     para que `chati doctor` pruebe cada skill con `skill.sh --check`.
   - Ejecutar como subproceso (nunca `source` ni `eval` del texto en el REPL);
     es higiene normal, no ceremonia de seguridad.
4. Registro de slashes: al arrancar, chati escanea `skills/` (y `~/.chati/skills`
   si existe), arma el mapa slash->ruta y RECHAZA (con aviso) colisiones. Gana el
   built-in, luego el del repo, al final el del usuario. `/help` y el TAB-complete
   salen del MISMO mapa (una sola fuente de verdad).
5. Conjunto de skills (built-in, cerrado). No hay `chati skill add`: los skills
   son las capacidades que YA trae chati, no algo que se instala. El set:
   `docr` (/ocr), `persona` (/persona), `web` (/web), `batch` (/batch, muchos
   comandos de un archivo), `file` (/file), `talk` (/talk, voz) y `shell`
   (/s, /sY). El nucleo del REPL (/model, /sessions, /settings, /help, /color,
   /new...) NO son skills; son built-ins que no se desactivan.

6. Activar/desactivar por skill (el candado). Estado persistente y global en
   `~/.chati/skills.disabled` (una linea por skill apagado). Comandos:
   `chati skill list` (muestra enabled/disabled), `chati skill enable <n>`,
   `chati skill disable <n>`. Un skill DESACTIVADO no registra su slash y NO
   inyecta su prompt de capacidad, asi que ni tu ni el modelo lo pueden usar.
   Esto es seguridad real: en una maquina compartida apagas `shell` (/s y /sY) y
   el modelo pierde del todo la ejecucion; apagas `web` si no quieres salidas a
   internet. Es distinto de los toggles por-sesion (THINK/WEB/AGENT ON/OFF, #60):
   disable = el skill no existe esta sesion; el toggle = prende/apaga uno que SI
   esta habilitado. `/sY` es el caso estrella: poderoso y peligroso, y ahora se
   puede dejar inalcanzable.

7. Dogfooding: `docr` es el primer skill migrado al contrato (es el candidato
   natural). Si el contrato no le queda comodo, esta mal el contrato.

## C. `chati doctor`

- `chati doctor` NO sabe de webui ni de searxng en concreto: itera `libexec` y
  skills, corre `--check` en cada uno y tabula. Agregar un componente = agregar un
  script con `--check`; doctor lo descubre solo.
- Lo unico propio de doctor: version de chati (y si hay release nuevo), Ollama
  vivo (`OLLAMA_API`), y modelos presentes (`/api/tags` vs el modelo activo).
- Primera version pragmatica: mientras no existan los `--check`, doctor chequea
  directo lo de hoy (Ollama, modelo, SearXNG sirviendo, webui en 8888, version) y
  luego migra a iterar `--check`.

## D. `/help` y autocomplete

- `/help` se reordena por ORIGEN: built-ins, subcomandos, skills del sistema,
  skills del usuario. Cada linea = slash + `summary` de la cabecera. Hoy confunde
  porque mezcla fuentes; separarlas lo arregla.
- TAB-complete dentro del REPL via `bind -x '"\t": _chati_complete'` + `compgen`
  sobre el mapa de slashes. Es fragil entre versiones de readline, asi que es
  OPCIONAL y `/help` nunca depende de el.

## Riesgos a vigilar

- macOS trae bash 3.2: nada de `declare -A` (arrays asociativos) si chati debe
  correr sin Homebrew. Usar dos arrays paralelos o archivos temporales. Verificar
  antes de disenar el mapa de slashes.
- readline/`bind -x` fragil entre versiones: TAB-complete opcional.
- No abrir la puerta a "skills en otros lenguajes" todavia: `skill.sh` es el unico
  ejecutable; si un skill necesita Python, lo invoca el. Mantiene el contrato y el
  tamper-check simples.

## Fases sugeridas (cada una branch -> PR -> release)

1. Dispatcher `chati <sub>` + `chati-common.sh` + `chati doctor` (version minima,
   chequeo directo). Shims de deprecacion para `ailocal`/`setup.sh`.
2. Contrato de skill ligero (en-repo) + `chati skill list/check` + migrar `docr`
   como primer skill (dogfood). doctor empieza a iterar `--check`. Sin `skill add`
   ni candados sha256: no hay codigo de terceros que contener.
3. `/help` reordenado por origen + TAB-complete opcional.
4. Migrar `/web` y `/persona` al contrato de skill.

## Decisiones (recomendadas, pendientes del OK de Carlos)

- `chati doctor` como SUBCOMANDO (no flag): encaja en el dispatcher sin caso
  especial, se autodescubre en `chati help`, y no mete logica de diagnostico al
  REPL. `--doctor` queda como alias de una linea que hace `exec chati doctor`.
- Skills de primera parte, pocos y curados, en `skills/` DENTRO del repo. Sin
  marketplace, sin instalar codigo de terceros, sin la maquinaria de seguridad que
  eso exigiria. `~/.chati/skills` queda como opcion de baja prioridad para el
  codigo propio de un usuario avanzado. Subcomandos en `libexec/` dentro del repo.

(El diseno es consenso con la sesion Dot, ya recortado al "entre menos, mejor" de
Carlos; falta su visto bueno para arrancar la Fase 1.)
