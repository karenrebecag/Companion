# Reference Brief: Catalogo unico de textos (UI, voz y modelo) en companion-next

Slug: catalogo-de-textos | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE
Decision de Karen (2026-09-30): formato `.strings`; L1 (target `CompanionCopy`) con ADR de capas; canales separados; usage descriptions (`InfoPlist.strings`) y semilla de memoria entran al alcance.

<!--
Toolchain observado en esta Mac: Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), Xcode 26.6 (17F113), macOS 26.
El codigo de SwiftPM citado es el tag swift-6.3.3-RELEASE (commit 5f6969f5b083b4415632114d4897c6f820761a7f),
el mismo que fija el brief recursos-empaquetados-bundle-module.
Conteos de la seccion 2 medidos con grep el 2026-09-30 sobre este worktree.
-->

## 1. Pregunta y decisiones abiertas

Pregunta (via orquestador, al que Karen delego las specs de siguientes pasos; no hay discovery): que forma debe tener un catalogo unico de textos en companion-next (SwiftPM, macOS 26, swift-tools 6.2, `defaultLocalization: "en"`), donde vive dada la division en capas, como se separan los textos hablados de los de pantalla y como se prueba que no falte una traduccion.

Decisiones que la spec tiene que tomar:

1. Formato del catalogo: String Catalog (`.xcstrings`), `.lproj/Localizable.strings` (+ `.stringsdict` si hay plurales), o tablas Swift tipadas.
2. Donde vive: hoy el catalogo esta en `CompanionUI` (MainActor) y `CompanionServices`/`CompanionCore` no pueden alcanzarlo; hay que decidir si baja a un target nuevo, si se inyecta una funcion de busqueda, o si Core/Services devuelven valores semanticos que la UI traduce.
3. Canales: que es texto de pantalla, que es texto hablado por la voz, y que es instruccion al modelo (prompt), y cual de esos entra al catalogo.
4. Pruebas: que garantiza, en `swift test`, en los gates y en el smoke de empaquetado, que ninguna clave quede sin traducir ni pinte la clave cruda.

Hallazgo que ordena el resto: con el sistema de build por defecto de Swift 6.3.3 (`native`), un `.xcstrings` se COPIA tal cual al bundle, sin compilarse a `.strings`; solo Xcode y el backend `swiftbuild` lo compilan (secciones 3 y 8).

## 2. Estado actual

- El manifiesto fija `swift-tools-version: 6.2` [repo:Package.swift:1]
- El manifiesto declara `defaultLocalization: "en"` [repo:Package.swift:8]
- `CompanionUI` declara recursos `Fonts` y `Mascot` con `.copy`; sus `en.lproj`/`es.lproj` entran al bundle sin declararse [repo:Package.swift:35]
- `CompanionUI` compila con `.defaultIsolation(MainActor.self)` [repo:Package.swift:36]
- `CompanionServices` no tiene `defaultIsolation` y solo declara `Skills` y `Diagram` como recursos (no hay `.lproj` en Services) [repo:Package.swift:27]
- El catalogo de UI es un `Localizable.strings` por idioma; el ingles se declara fuente en la cabecera del archivo [repo:Sources/CompanionUI/en.lproj/Localizable.strings:1]
- Ambos catalogos tienen 696 lineas y 645 claves cada uno (conteo con grep de lineas que empiezan por comilla) [repo:Sources/CompanionUI/es.lproj/Localizable.strings:32]
- 70 lineas del catalogo ingles llevan especificadores de formato (`%@`, `%d`, `%ld`...) [repo:Sources/CompanionUI/en.lproj/Localizable.strings:22]
- `Localized` es `package enum` dentro de CompanionUI, por lo tanto `@MainActor` por la isolation por defecto del target [repo:Sources/CompanionUI/Localization/Localized.swift:10]
- `Localized.language` prefiere un pin `TaskLocal` y si no hay, lee un `source` global protegido por `NSLock` [repo:Sources/CompanionUI/Localization/Localized.swift:40]
- `Localized.string(_:language:)` busca en `UIResourceBundle.bundle`, el resolver de 21c [repo:Sources/CompanionUI/Localization/Localized.swift:63]
- La busqueda abre el sub-bundle `<idioma>.lproj` con `Bundle(path:)` en cada llamada, sin cache [repo:Sources/CompanionUI/Localization/Localized.swift:81]
- El fallback a ingles se dispara solo si `bundle(for:)` devuelve nil (falta el `.lproj` entero), porque `localizedString(forKey:value:table:)` devuelve `String` no opcional [repo:Sources/CompanionUI/Localization/Localized.swift:68]
- El comentario promete que el ingles es "lo ultimo antes de la clave cruda", cosa que el codigo solo cumple cuando falta el `.lproj`, no cuando falta una clave dentro de `es.lproj` [repo:Sources/CompanionUI/Localization/Localized.swift:73]
- `UIResourceBundle` es `nonisolated enum` y resuelve el bundle una sola vez via `ResourceBundleLocator`; nil pinta claves crudas y registra un error [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:8]
- `UIResourceBundle.name` fija el nombre `Companion_CompanionUI.bundle` [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:11]
- El probe de empaquetado comprueba `lproj.en` y `lproj.es` con la clave `chat.job.done`, cuyo espanol difiere del ingles [repo:Sources/CompanionUI/Platform/UIResourceProbe.swift:11]
- `AppLanguage` (Core) tiene dos casos, `en` y `es`, y es `CaseIterable` [repo:Sources/CompanionCore/Platform/AppLanguage.swift:7]
- CompanionUI llama `Localized.string(` 569 veces en 73 archivos; el mayor es `SettingsPages.swift` con 40 [repo:Sources/CompanionUI/Settings/SettingsPages.swift:17]
- CompanionUI no tiene lineas de codigo con literales en espanol fuera de comentarios (grep de `"...[áéíóúñ¿¡]..."`); su copy sale de accesores como este [repo:Sources/CompanionUI/Chat/ChatCopy.swift:8]
- CompanionCore tiene 224 lineas con literales en espanol en 33 archivos; el mayor es `Escalation+Copy.swift` con 18 `case .es` [repo:Sources/CompanionCore/Delegation/Escalation+Copy.swift:13]
- Tipos `*Copy` en Core con tablas bilingues en Swift: `ApprovalCopy` [repo:Sources/CompanionCore/Approvals/ApprovalCopy.swift:35]
- `ApprovalCopy` guarda sus palabras en un `switch (word, language)` con un caso por idioma [repo:Sources/CompanionCore/Approvals/ApprovalCopy.swift:302]
- `ApprovalCopy.toolLabel` usa un ternario `language == .es ? noun.es : noun.en`, que hace del ingles el valor implicito de cualquier idioma nuevo [repo:Sources/CompanionCore/Approvals/ApprovalCopy.swift:122]
- `BridgeCopy` explica por que vive fuera del catalogo de UI: lo construye un actor de Services que no alcanza `Localized` [repo:Sources/CompanionCore/Bridge/BridgeCopy.swift:3]
- Otros `*Copy` en Core: `BrowserCopy` [repo:Sources/CompanionCore/Browser/BrowserCopy.swift:5]
- Otros `*Copy` en Core: `DecisionCopy` [repo:Sources/CompanionCore/Decision/DecisionRouting.swift:197]
- Otros `*Copy` en Core: `ParentToolCopy` [repo:Sources/CompanionCore/Tools/ParentTools.swift:352]
- `*Copy` en UI que pasan por `Localized`: `ChatCopy` [repo:Sources/CompanionUI/Chat/ChatCopy.swift:7]
- `VoiceCopy` expone `static var` computadas sobre `Localized`, asi que siguen un cambio de idioma en caliente [repo:Sources/CompanionUI/Voice/VoiceCopy.swift:5]
- Hay trece enums `*Copy` mas en UI (Island, Apps, Settings, Feedback, Home...), por ejemplo `IslandCopy` [repo:Sources/CompanionUI/Island/IslandCopy.swift:5]
- En Services, `VoiceAttachmentCopy` se declara "model-facing" y viaja en el idioma de la sesion [repo:Sources/CompanionServices/Voice/Session/VoiceSessionAttachments.swift:23]
- CompanionServices tiene 10 lineas con literales en espanol en 5 archivos; `JobRunner` elige idioma con un booleano `english ? ... : ...` [repo:Sources/CompanionServices/Delegation/JobRunner.swift:81]
- `RealtimeRuntime.functionRefusal` (Services) dice "Jobs will be available in a future version." [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:19]
- La misma frase existe como clave `voice.function.refusal` del catalogo de UI; `VoiceCopy.functionRefusal` no tiene llamadores fuera de su definicion (grep), la copia viva es la de Services [repo:Sources/CompanionUI/en.lproj/Localizable.strings:43]
- `RealtimeRuntime.functionAccepted` es una instruccion al modelo de voz ("say you are working on it"), no un texto que el usuario lea [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:12]
- `OpenAITTS` manda al TTS una instruccion de estilo en espanol ("Habla en espanol de Mexico...") [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:32]
- `FileMemoryStore` siembra el archivo de memoria solo en espanol ("# Sobre la usuaria") [repo:Sources/CompanionServices/Storage/FileMemoryStore.swift:28]
- CompanionApp tiene un toast solo en espanol: "Versión ... disponible — Ajustes → Sistema" [repo:Sources/CompanionApp/CompanionMainWindow.swift:93]
- El gate de copy solo mira `Text(`, `.help(` y `.accessibilityLabel(` dentro de CompanionUI, asi que no ve ese toast de App ni el copy de Core/Services [repo:scripts/gates.sh:225]
- Los usage descriptions del Info.plist (microfono, voz, ubicacion...) se escriben solo en ingles dentro de `bundle.sh`; no hay `InfoPlist.strings` [repo:scripts/bundle.sh:86]
- Test existente: `LocalizedTests` exige las mismas claves en `en` y `es` [repo:Tests/CompanionTests/LocalizedTests.swift:15]
- `LocalizedTests` extrae las claves partiendo lineas que empiezan por comilla, no con el parser de Foundation [repo:Tests/CompanionTests/LocalizedTests.swift:59]
- `LocalizedTests` lee el catalogo con `Bundle.module` bajo `@testable import CompanionUI` [repo:Tests/CompanionTests/LocalizedTests.swift:53]
- Test existente: `CopyLeakTests` exige que el copy de error salga del catalogo y nunca interpole el texto del error [repo:Tests/CompanionTests/CopyLeakTests.swift:36]
- `CopyLeakTests` comprueba que ningun catalogo repita una clave [repo:Tests/CompanionTests/CopyLeakTests.swift:63]
- Test existente: `CatalogLeakTests` cubre labels que antes eran literales y dice que "el gate de catalogo no ve switch statements" [repo:Tests/CompanionTests/CatalogLeakTests.swift:6]
- Lo mas cerca de un control de formato es que el aviso no quede con `%@` sin rellenar; ningun test compara especificadores entre `en` y `es` (grep sobre Tests) [repo:Tests/CompanionTests/CopyLeakTests.swift:57]
- La wave 9 ya eligio `.strings` sobre `.xcstrings` porque SwiftPM compila los `.lproj` con `swift build` y el catalogo moderno depende de tooling de Xcode [repo:docs/specs/wave-9-ajena.md:122]
- La arquitectura promete que Command Line Tools bastan para compilar, sin proyecto de Xcode [repo:docs/ARCHITECTURE.md:3]
- La arquitectura define Core como dominio puro, "no Apple frameworks beyond Foundation" [repo:docs/ARCHITECTURE.md:12]
- El smoke de empaquetado enumera exactamente dos bundles, UI y Services [repo:scripts/package-smoke.sh:17]
- El smoke exige que sin bundles fallen `lproj.en` y `lproj.es` entre otras comprobaciones [repo:scripts/package-smoke.sh:162]
Contextos: app instalada (`/Applications/Companion.app`, bundles en `Contents/Resources` via el resolver de 21c), `swift test` (runner de Swift Testing, lee `.build/debug`), smoke de empaquetado (`scripts/package-smoke.sh`, app firmada con el checkout ilegible por `sandbox-exec`), `swift run companion` desde el checkout, y los modelos remotos (Realtime, chat, TTS) que reciben el texto de canal modelo

## 3. Fuentes primarias

- SwiftPM 6.3.3: el `--build-system` por defecto es `native` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/Options.swift#L544-L549@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: `.xcstrings` es un recurso `processResource` desde tools 5.9 (la regla `stringCatalog`) [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/PackageLoading/TargetSourcesBuilder.swift#L792-L799@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3, backend native: para `.copy` y `.process` el manifiesto de build solo agrega un comando de copia por recurso; no hay paso que compile `.xcstrings` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildManifest/LLBuildManifestBuilder+Resources.swift#L31-L41@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3, backend swiftbuild: agrega el String Catalog tambien como fuente para generar simbolos, que es la ruta de Xcode [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift#L341-L347@swift-6.3.3-RELEASE]
- Mantenedor de SwiftPM (neonichu, 2023): "SwiftPM's build system does not support .xcstrings files, only Xcode does" [doc:https://github.com/swiftlang/swift-package-manager/issues/6993@2023-10-12]
- WWDC23 "Discover String Catalogs": los catalogos "are designed specifically for interaction within an Xcode project" y "at build time, these files compile to .strings and .stringsdict files" [doc:https://developer.apple.com/videos/play/wwdc2023/10155/@WWDC23]
- WWDC23, misma sesion: las cadenas "manually-managed" nunca las actualiza ni borra Xcode, util para claves construidas dinamicamente [doc:https://developer.apple.com/videos/play/wwdc2023/10155/@WWDC23]
- SE-0278: `defaultLocalization` es el fallback cuando ninguna otra localizacion encaja; los recursos localizados van en carpetas `<tag>.lproj` y solo se detectan con la regla `.process` [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0278-package-manager-localized-resources.md@42ee8fb0d529487e1da8730b6a4b1a65eaa5d121]
- Apple, "Localizing package resources": los localizados van en directorios `.lproj` y se leen con `NSLocalizedString(..., bundle: Bundle.module, ...)` [doc:https://developer.apple.com/documentation/xcode/localizing-package-resources@2026-09-30]
- Apple, `Bundle.localizedString(forKey:value:table:)`: "If key is not found and value is nil or an empty string, returns key" [doc:https://developer.apple.com/documentation/foundation/bundle/localizedstring(forkey:value:table:)@2026-09-30]
- Apple, misma pagina: con la default `NSShowNonLocalizedStrings` el metodo registra en consola cada clave no encontrada y la devuelve en mayusculas [doc:https://developer.apple.com/documentation/foundation/bundle/localizedstring(forkey:value:table:)@2026-09-30]
- Apple, `String(localized:table:bundle:locale:comment:)`: el parametro `locale` solo formatea valores interpolados y "doesn't change which locale the system uses to look up the localized string" [doc:https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:)@macOS-12]
- SE-0466: con `defaultIsolation(MainActor.self)` las declaraciones del modulo se infieren `@MainActor` [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0466-control-default-actor-isolation.md@42ee8fb0d529487e1da8730b6a4b1a65eaa5d121]
- SwiftPM issue abierta: el `Bundle.module` sintetizado hereda `@MainActor` en targets con esa isolation por defecto y no se puede usar desde codigo `nonisolated` (reproducido con Swift 6.3) [doc:https://github.com/swiftlang/swift-package-manager/issues/9656@2026-02-17]
- Apple HIG, Siri: la respuesta de voz "can stand alone" sin depender de elementos visuales, y debe ser "as succinct as possible" [doc:https://developer.apple.com/design/human-interface-guidelines/siri@2026-09-30]
- Apple, "Managing your app's information property list": hay que localizar `CFBundleDisplayName` y todas las claves `UsageDescription` [doc:https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list@2026-09-30]

## 4. Implementaciones de referencia

- CodexBar (steipete; app de barra de menu macOS construida con SwiftPM CLI y script de empaquetado propio, igual que companion-next; commit del 2026-09-30) usa `.lproj/Localizable.strings` + `Localizable.stringsdict`, no `.xcstrings` [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Resources/es.lproj/Localizable.stringsdict@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar resuelve el idioma elegido en la app con un `@TaskLocal` de override, el mismo seam que `Localized.scoped` [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Localization.swift#L4-L6@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar cachea los sub-bundles `.lproj` por idioma porque `Bundle(url:)`/`Bundle(path:)` en cada `L(...)` resulto "surprisingly hot" en el hilo principal (su issue #1347) [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Localization.swift#L51-L97@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar detecta la clave faltante comparando `value != key` y solo entonces cae al `en.lproj` [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Localization.swift#L256-L271@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar prueba cada catalogo leyendolo con `NSDictionary(contentsOf:)` y verifica que una frase con formato tenga exactamente un `%@` en cada idioma [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Tests/CodexBarTests/LocalizationLanguageCatalogTests.swift#L33-L49@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar tiene un test que lee el fuente y prohibe literales en ingles concretos en superficies de UI [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Tests/CodexBarTests/UserFacingLocalizationCoverageTests.swift#L7-L20@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- Mastodon iOS (organizacion mastodon, ~2.3k estrellas, push del 2026-09-30) aisla el texto en un target `MastodonLocalization` sin dependencias propias, del que dependen `MastodonCore` y `MastodonSDK` [ref:https://github.com/mastodon/mastodon-ios/blob/69cc4fecd0fb425a443c8ddd28685f911b06d46a/MastodonSDK/Package.swift#L74-L104@69cc4fecd0fb425a443c8ddd28685f911b06d46a]
- Mastodon expone accesores tipados (`L10n`, generado en origen por SwiftGen) que el codigo llama en vez de claves sueltas [ref:https://github.com/mastodon/mastodon-ios/blob/69cc4fecd0fb425a443c8ddd28685f911b06d46a/MastodonSDK/Sources/MastodonLocalization/Generated/Strings.swift#L14-L21@69cc4fecd0fb425a443c8ddd28685f911b06d46a]
- Mastodon migro a `.xcstrings` intercambiados con Crowdin y ahora mantiene a mano esos accesores [ref:https://github.com/mastodon/mastodon-ios/blob/69cc4fecd0fb425a443c8ddd28685f911b06d46a/MastodonSDK/Sources/MastodonLocalization/Generated/Strings.swift#L1-L4@69cc4fecd0fb425a443c8ddd28685f911b06d46a]
- SwiftGen (plantilla `structured-swift5`, ~9.5k estrellas; ultimo release 6.6.3 en 2024-03, actividad baja): el accesor tipado por defecto es `static let`, y la variante con `lookupFunction` es `static var` [ref:https://github.com/SwiftGen/SwiftGen/blob/f7c23b63053e5a8aab4a4dbb633b24920bbb9436/Sources/SwiftGenCLI/templates/strings/structured-swift5.stencil#L44-L49@f7c23b63053e5a8aab4a4dbb633b24920bbb9436]
- SwiftGen resuelve con `localizedString(forKey:value:table:)` pasando el ingles como `value`, asi una clave faltante devuelve el texto fuente y no la clave [ref:https://github.com/SwiftGen/SwiftGen/blob/f7c23b63053e5a8aab4a4dbb633b24920bbb9436/Sources/SwiftGenCLI/templates/strings/structured-swift5.stencil#L78-L95@f7c23b63053e5a8aab4a4dbb633b24920bbb9436]

## 5. Opciones

Decision 1, formato:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `.xcstrings` con `swift build` native | Editor de Xcode, estados New/Stale, un JSON para ambos idiomas | El backend por defecto de 6.3.3 lo copia sin compilar; `xcstringstool` vive en Xcode.app, no en CLT; rompe la promesa de ARCHITECTURE | alta | No |
| A2. `.xcstrings` + `--build-system swiftbuild` o plugin que llame `xcstringstool` | Catalogo moderno compilado | Cambia `bundle.sh`, gates, resolver y smoke; issues abiertas del backend swiftbuild con `xcstringstool`; dependencia de Xcode | alta | No por ahora; reabrir cuando swiftbuild sea el default |
| B. `.lproj/Localizable.strings` (+ `.stringsdict` para plurales) | Ya funciona en los tres contextos; lo verifica el smoke; es lo que hace CodexBar con SwiftPM CLI | Sin estados de traduccion; la completitud la dan tests propios | baja | Si |
| C. Tablas Swift tipadas (`switch` exhaustivo sobre `AppLanguage`) | Completitud en compilacion; sin I/O; usable desde Core puro y desde actores | El copy se edita en Swift; no sirve a un traductor; mezcla texto y codigo | baja | Solo para el canal modelo (prompts) |

Decision 2, donde vive el catalogo de texto para personas:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| L1. Target nuevo `CompanionCopy` (Foundation, sin `defaultIsolation`, recursos `.lproj`), depende de Core; lo usan Services y UI | Un solo catalogo alcanzable desde actores de Services y desde la UI; patron de Mastodon; `Bundle.module` queda `nonisolated` | Toca `Package.swift` (contrato entre modulos); tercer bundle para el resolver 21c, el probe y el smoke | media | Si, con escalado |
| L2. Catalogo sigue en UI; Services recibe por inyeccion una funcion `(clave, idioma) -> String` desde App | Sin cambiar `Package.swift` | Plumbing por cada actor; la clave cruza capas como `String`; `Localized` tendria que volverse `nonisolated` | media | Alternativa si Karen no quiere target nuevo |
| L3. Estado actual (UI en `.strings`, Core/Services en tablas Swift) | Nada que migrar | Dos fuentes de verdad; duplicados ya vivos (`voice.function.refusal`); literales monolingues fuera del gate | nula | No |

Decision 3, canales: pantalla y voz hablada al usuario entran al catalogo (tablas separadas, p. ej. `Localizable` y `Spoken`); las instrucciones al modelo quedan como tablas Swift tipadas en Core, fuera del catalogo. Core no pasa a leer bundles: donde hoy arma texto para personas (aprobaciones, puente, navegador), devuelve valores semanticos y Services/UI los traducen.

## 6. Evidencia en contra

- Contra B: los String Catalogs son el formato que Apple promueve y dan estados de traduccion; quedarse en `.strings` pierde ese flujo. Se acepta: con el toolchain en uso no se compilan fuera de Xcode, y el propio Apple dice que estan "designed specifically for interaction within an Xcode project" [doc:https://developer.apple.com/videos/play/wwdc2023/10155/@WWDC23]
- Contra B: Swift 6.4 ya trae `swiftbuild` como backend (el issue 10559 de septiembre 2026 lo usa por defecto), asi que la razon de A caduca al subir de toolchain. Se resuelve fijando la version en `Versiones:` y marcando el brief para reinvestigar al pasar a 6.4 [doc:https://github.com/swiftlang/swift-package-manager/issues/10559@2026-09-20]
- Contra L1: un target nuevo es mas superficie (tercer bundle, tercer probe) y SE-0271 dice que el nombre del bundle es implementation-defined. Se resuelve con el mismo `ResourceBundleLocator` y el mismo smoke que ya cubren UI y Services [repo:scripts/package-smoke.sh:17]
- Contra separar tablas de voz: la HIG de Siri pide que la respuesta funcione en voz y en pantalla a la vez, lo que empuja a UNA frase para ambos. Se acepta parcialmente: la misma clave sirve para ambos canales cuando el texto se sostiene solo; solo lo que se pronuncia distinto (sin simbolos, sin "→", mas corto) lleva clave `Spoken` propia [doc:https://developer.apple.com/design/human-interface-guidelines/siri@2026-09-30]
- Contra C para prompts: un prompt en tabla Swift no lo revisa un traductor, y hoy el mismo archivo mezcla textos para personas y para el modelo. Se acepta: se separan por canal y el prompt se prueba con los tests del modelo, no con paridad de claves [repo:Sources/CompanionCore/Delegation/Escalation+Copy.swift:3]

## 7. Ejemplares y anti-ejemplos

- Bien: clave faltante detectada por `value != key` y fallback explicito al ingles (CodexBar `codexBarLocalizedString`) [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Localization.swift#L256-L271@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]

```swift
let value = bundle.localizedString(forKey: key, value: nil, table: nil)
if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value != key { return value }
// only now fall back to en.lproj
```

- Mal: `?? fallback` sobre `bundle(for:)?.localizedString(...)` solo cubre el `.lproj` ausente; una clave ausente en `es` devuelve la clave cruda [repo:Sources/CompanionUI/Localization/Localized.swift:68]
- Bien: leer el catalogo con el parser de Foundation (`NSDictionary(contentsOf:)`) y comparar especificadores de formato por clave (CodexBar) [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Tests/CodexBarTests/LocalizationLanguageCatalogTests.swift#L42-L47@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- Mal: partir lineas por comillas; no ve valores multilinea ni escapes y no puede comparar formatos [repo:Tests/CompanionTests/LocalizedTests.swift:59]
- Bien: accesor computado que sigue el cambio de idioma en caliente (`static var` sobre la busqueda) [repo:Sources/CompanionUI/Voice/VoiceCopy.swift:5]
- Mal: accesor `static let`, que congela el idioma del primer acceso (plantilla por defecto de SwiftGen) [ref:https://github.com/SwiftGen/SwiftGen/blob/f7c23b63053e5a8aab4a4dbb633b24920bbb9436/Sources/SwiftGenCLI/templates/strings/structured-swift5.stencil#L49@f7c23b63053e5a8aab4a4dbb633b24920bbb9436]
- Bien, para el canal modelo: `switch language { case .en: ...; case .es: ... }` sin `default`, que obliga a traducir al agregar un idioma [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:18]
- Mal: ternario o booleano `english ? ... : ...`, que hace del espanol el valor de cualquier idioma nuevo sin que el compilador avise [repo:Sources/CompanionServices/Delegation/JobRunner.swift:81]
- Bien: un target de localizacion sin dependencias del que cuelgan las capas de arriba (Mastodon) [ref:https://github.com/mastodon/mastodon-ios/blob/69cc4fecd0fb425a443c8ddd28685f911b06d46a/MastodonSDK/Package.swift#L93-L96@69cc4fecd0fb425a443c8ddd28685f911b06d46a]

## 8. Trampas

- `.xcstrings` bajo `swift build` native se copia como JSON al bundle y no produce `en.lproj/Localizable.strings`; en la app instalada el probe `lproj.en`/`lproj.es` fallaria y el smoke lo atraparia [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildManifest/LLBuildManifestBuilder+Resources.swift#L31-L41@swift-6.3.3-RELEASE]
- `.xcstrings` como unico recurso de un target no genera `Bundle.module` en el backend native (issue 6993) [doc:https://github.com/swiftlang/swift-package-manager/issues/6993@2023-10-12]
  - Nota del verificador (2026-09-30): la issue es de 5.9; en 6.3.3 `xcstrings` es regla `processResource` (seccion 3), asi que este mecanismo probablemente ya no aplica. No cambia la recomendacion B; queda sin verificar [doc:https://github.com/swiftlang/swift-package-manager/issues/6993@2023-10-12]
- `String(localized:bundle:locale:)` NO elige idioma por `locale`; el selector de idioma de la app necesita seguir abriendo el sub-bundle `<idioma>.lproj` [doc:https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:)@macOS-12]
- Un target con `defaultIsolation(MainActor.self)` vuelve `@MainActor` tanto a `Localized` como al `Bundle.module` sintetizado, y ningun actor de Services puede usarlos; un target de copy nuevo no debe llevar esa isolation [doc:https://github.com/swiftlang/swift-package-manager/issues/9656@2026-02-17]
- Nunca leer `Bundle.module` directo desde el catalogo nuevo: el accessor de SwiftPM hace `fatalError` si no encuentra el bundle; va por `ResourceBundleLocator` como UI y Services [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:5]
- Un bundle nuevo que no se agregue a `BUNDLES` del smoke pasa verde en esta Mac por el fallback a `.build` y truena en otra [repo:scripts/package-smoke.sh:17]
- `Bundle(path:)` por llamada en `Localized` es el mismo patron que CodexBar midio como caliente en el hilo principal [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBar/Localization.swift#L51-L57@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- Los usage descriptions de permisos los muestra el sistema en el idioma del sistema via `InfoPlist.strings` del bundle principal, no en el idioma elegido en la app; hoy solo existen en ingles [doc:https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list@2026-09-30]
- Contexto app instalada: el catalogo se lee de `Contents/Resources/<bundle>/<idioma>.lproj` via el resolver 21c; lo prueba `UIResourceProbe` [repo:Sources/CompanionUI/Platform/UIResourceProbe.swift:25]
- Contexto `swift test`: los tests leen el catalogo con `Bundle.module` del `.build/debug`; un test de paridad pasa aunque el bundle empaquetado este mal, por eso el smoke es la unica prueba del layout real [repo:Tests/CompanionTests/LocalizedTests.swift:53]
- Contexto `swift test`: los tests corren en paralelo y ~20 archivos fijan idioma; todo test nuevo de copy va dentro de `Localized.scoped`, nunca asignando el global [repo:Sources/CompanionUI/Localization/Localized.swift:24]
- Contexto smoke: el checkout es ilegible, asi que una clave que solo resuelve por el fallback a `.build` aparece como clave cruda en el probe [repo:scripts/package-smoke.sh:37]
- Contexto modelos remotos: el texto de canal modelo cambia la conducta del modelo (idioma en que responde, narracion); moverlo a un catalogo editable por traductores cambiaria comportamiento sin test [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:8]
- Contexto `swift run`: `Bundle.main` es el directorio del ejecutable en `.build`; se resuelve igual que en tests y no prueba el empaquetado [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:26]

## 9. Incertidumbre

- ASSUMPTION: Foundation en macOS 26 no lee en runtime un `Localizable.xcstrings` copiado crudo al bundle (sin `.lproj` compilados), asi que `localizedString` devolveria la clave. prueba: paquete minimo con `defaultLocalization: "en"` y solo `Localizable.xcstrings` (en/es) mas un `.lproj` vacio para forzar el bundle, `swift build` native, listar el bundle y llamar `localizedString` sobre `es.lproj`.
- ASSUMPTION: con `swift build --build-system swiftbuild` en 6.3.3 el `.xcstrings` se compila a `en.lproj`/`es.lproj` y el bundle conserva el nombre `Companion_CompanionUI.bundle`. prueba: el mismo paquete minimo con `--build-system swiftbuild`, `ls` del bundle resultante y del nombre.
- ASSUMPTION: la ruta de fallback de `Localized` pinta la clave cruda cuando falta una clave solo en `es` (derivado del codigo y de la doc de `localizedString`, no ejecutado). prueba: test que construye un bundle temporal con `en.lproj` completo y `es.lproj` sin una clave y llama `Localized.string(_:language:in:)` con `.es`.
- ASSUMPTION: el costo de `Bundle(path:)` por llamada en `Localized` es medible en companion-next como lo fue en CodexBar. prueba: medir 10k llamadas a `Localized.string` con y sin cache de sub-bundles.
- ASSUMPTION: los conteos de la seccion 2 (224 lineas en Core, 10 en Services, 1 en App) cubren el copy monolingue; el grep solo ve literales con acentos o signos espanoles, no el ingles-solo. prueba: inventario manual por archivo de los 33+5+1 archivos, clasificando cada literal en pantalla, voz o modelo.
- Observado en esta Mac (sin URL citable): `xcstringstool` existe solo en `/Applications/Xcode.app/Contents/Developer/usr/bin`, no en `/Library/Developer/CommandLineTools/usr/bin`; su subcomando `compile` produce `stringsAndStringsdict`.
- [NEEDS CLARIFICATION: se acepta un target nuevo `CompanionCopy` en `Package.swift` (L1), o se prefiere inyectar la busqueda desde App sin tocar el manifiesto (L2)?]
- [NEEDS CLARIFICATION: los textos de permisos del sistema (usage descriptions) entran al alcance del catalogo, sabiendo que siguen el idioma del sistema y no el elegido en la app?]
- [NEEDS CLARIFICATION: la semilla del archivo de memoria ("# Sobre la usuaria") es copy de la usuaria o contenido suyo que no se traduce?]

## 10. Checklist de estandar

- [ ] El formato del catalogo es `.lproj/Localizable.strings` (y `.stringsdict` si hay plurales); ningun `.xcstrings` entra al repo mientras el backend por defecto sea `native`
- [ ] Cada cadena del producto esta clasificada en uno de tres canales: pantalla, voz hablada al usuario, instruccion al modelo
- [ ] Pantalla y voz salen de un solo catalogo alcanzable desde Services y UI (target nuevo o inyeccion, segun decida Karen); no queda ninguna copia duplicada de la misma frase en Swift
- [ ] Las instrucciones al modelo viven en tablas Swift en Core con `switch` exhaustivo sobre `AppLanguage`, sin `default:` ni ternarios de idioma
- [ ] El API de copy es tipado (enums `*Copy` con `static var` o funciones); ninguna vista ni actor llama a la busqueda con una clave suelta
- [ ] Una clave ausente en `es` devuelve el texto ingles, nunca la clave cruda, y un test lo prueba con un bundle temporal
- [ ] Los sub-bundles `.lproj` se resuelven una vez por idioma (cache), no en cada llamada
- [ ] El test de paridad lee los catalogos con el parser de Foundation y exige: mismas claves, sin duplicados, sin valores vacios, y los mismos especificadores de formato por clave en `en` y `es`
- [ ] Un test o gate comprueba que toda clave usada en el codigo existe en `en.lproj` y que no quedan claves sin uso
- [ ] El gate de copy cubre todos los targets (App incluido): ningun literal con texto de usuario fuera de los archivos de catalogo o de tablas de canal modelo
- [ ] Si se crea un bundle nuevo, esta en el resolver 21c, en el probe (`lproj.en`/`lproj.es`) y en `BUNDLES` de `package-smoke.sh`, y el smoke pasa con el checkout ilegible
- [ ] Todo test nuevo de copy fija idioma con `Localized.scoped`, nunca asignando el global

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SwiftPM `Options.swift` (build system por defecto) | swiftlang | swift-6.3.3-RELEASE 5f6969f | 2026-09-30 | high |
| 2 | SwiftPM `TargetSourcesBuilder.swift` (regla stringCatalog) | swiftlang | swift-6.3.3-RELEASE 5f6969f | 2026-09-30 | high |
| 3 | SwiftPM `LLBuildManifestBuilder+Resources.swift` | swiftlang | swift-6.3.3-RELEASE 5f6969f | 2026-09-30 | high |
| 4 | SwiftPM `PackagePIFProjectBuilder.swift` | swiftlang | swift-6.3.3-RELEASE 5f6969f | 2026-09-30 | high |
| 5 | SwiftPM issue 6993 (xcstrings sin Bundle.module) | swiftlang | 2023-10-12 | 2026-09-30 | high |
| 6 | SwiftPM issue 9656 (Bundle.module y MainActor) | swiftlang | 2026-02-17 | 2026-09-30 | medium |
| 7 | SwiftPM issue 10559 (swiftbuild por defecto en 6.4) | swiftlang | 2026-09-20 | 2026-09-30 | medium |
| 8 | WWDC23 Discover String Catalogs | Apple | 2023 | 2026-09-30 | high |
| 9 | Localizing package resources | Apple | 2026-09-30 | 2026-09-30 | high |
| 10 | Bundle.localizedString(forKey:value:table:) | Apple | 2026-09-30 | 2026-09-30 | high |
| 11 | String(localized:table:bundle:locale:comment:) | Apple | macOS 12+ | 2026-09-30 | high |
| 12 | SE-0278 Package Manager Localized Resources | swift-evolution | 42ee8fb | 2026-09-30 | high |
| 13 | SE-0466 Control default actor isolation inference | swift-evolution | 42ee8fb | 2026-09-30 | high |
| 14 | HIG Siri | Apple | 2026-09-30 | 2026-09-30 | medium |
| 15 | Managing your app's information property list | Apple | 2026-09-30 | 2026-09-30 | high |
| 16 | CodexBar Localization.swift y tests | steipete | 5de8b9c | 2026-09-30 | high |
| 17 | Mastodon iOS MastodonLocalization | mastodon | 69cc4fe | 2026-09-30 | high |
| 18 | SwiftGen structured-swift5.stencil | SwiftGen | f7c23b6 (6.6.3) | 2026-09-30 | medium |
| 19 | Sam Deane, Localizable String Catalogues in Swift Packages (secundaria, confirma que swift build/test no genera simbolos) | elegantchaos.com | 2026-02-12 | 2026-09-30 | medium |
