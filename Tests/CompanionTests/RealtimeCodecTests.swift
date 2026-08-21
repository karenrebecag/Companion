import CompanionCore
import Foundation
import Testing

@Test @MainActor func realtimeCodecTests() {
    testRealtimeParse()
    testRealtimeSessionUpdate()
    testRealtimeSeed()
    testRealtimeSystemItem()
    testApprovalTool()
    testRealtimeControlFrames()
    testRealtimeAppendAudio()
}

@MainActor func testRealtimeParse() {
    expect(RealtimeCodec.parse("basura sin json") == .ignored,
           "parse: basura se ignora")
    expect(RealtimeCodec.parse(#"{"type":"rate_limits.updated"}"#) == .ignored,
           "parse: evento desconocido se ignora")
    expect(RealtimeCodec.parse(#"{"type":"input_audio_buffer.speech_started"}"#) == .speechStarted,
           "parse: speech_started")
    expect(RealtimeCodec.parse(#"{"type":"input_audio_buffer.speech_stopped"}"#) == .speechStopped,
           "parse: speech_stopped")
    expect(RealtimeCodec.parse(#"{"type":"response.done"}"#) == .responseDone,
           "parse: response.done")
    expect(RealtimeCodec.parse(#"{"type":"output_audio_buffer.started"}"#)
           == .agentAudioStarted, "parse: la bocina del webrtc empezó")
    expect(RealtimeCodec.parse(#"{"type":"output_audio_buffer.stopped"}"#)
           == .agentAudioStopped, "parse: la bocina del webrtc calló")
    expect(RealtimeCodec.parse(#"{"type":"output_audio_buffer.cleared"}"#)
           == .agentAudioStopped, "parse: el clear también calla")

    let b64 = Data("hola".utf8).base64EncodedString()
    expect(RealtimeCodec.parse("{\"type\":\"response.output_audio.delta\",\"delta\":\"\(b64)\"}")
           == .audioDelta(Data("hola".utf8)),
           "parse: audio delta decodifica el base64")

    expect(RealtimeCodec.parse(#"{"type":"response.output_audio_transcript.delta","delta":"Ho"}"#)
           == .assistantTranscriptDelta("Ho"), "parse: transcript delta")
    expect(RealtimeCodec.parse(#"{"type":"response.output_audio_transcript.done","transcript":"Hola."}"#)
           == .assistantTranscriptDone("Hola."), "parse: transcript done")
    expect(RealtimeCodec.parse(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":" qué hora es "}"#)
           == .userTranscript("qué hora es"),
           "parse: transcript del usuario llega recortado")
    expect(RealtimeCodec.parse(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"  "}"#)
           == .ignored, "parse: transcript vacío se ignora")

    expect(RealtimeCodec.parse(#"{"type":"response.function_call_arguments.done","name":"delegate","arguments":"{\"goal\":\"x\"}","call_id":"c1"}"#)
           == .functionCall(name: "delegate", arguments: #"{"goal":"x"}"#, callId: "c1"),
           "parse: function call trae name, arguments y call_id")
    expect(RealtimeCodec.parse(#"{"type":"error","error":{"message":"nope"}}"#)
           == .serverError("nope"), "parse: error trae el mensaje")

    expect(RealtimeCodec.parse("") == .ignored, "parse: vacío se ignora")
    expect(RealtimeCodec.parse("[]") == .ignored, "parse: un array no es evento")
    expect(RealtimeCodec.parse(#"{"type":1}"#) == .ignored,
           "parse: type no-string se ignora")
    expect(RealtimeCodec.parse(#"{"type":"session.created"}"#) == .sessionCreated,
           "parse: session.created")
    expect(RealtimeCodec.parse(#"{"type":"session.updated"}"#) == .sessionUpdated,
           "parse: session.updated")
    expect(RealtimeCodec.parse(#"{"type":"response.output_audio_transcript.delta"}"#)
           == .assistantTranscriptDelta(""),
           "parse: transcript delta ausente queda cadena vacía")
    expect(RealtimeCodec.parse(#"{"type":"response.output_audio_transcript.done","transcript":"  "}"#)
           == .ignored, "parse: transcript done vacío se ignora")
    expect(RealtimeCodec.parse(#"{"type":"response.output_audio.delta","delta":""}"#)
           == .ignored, "parse: audio delta vacío se ignora")
    expect(RealtimeCodec.parse(#"{"type":"response.output_audio.delta","delta":"@@@"}"#)
           == .ignored, "parse: base64 inválido se ignora")
    expect(RealtimeCodec.parse(#"{"type":"response.function_call_arguments.done","name":"delegate","arguments":"{}"}"#)
           == .ignored, "parse: function call sin call_id se ignora")
    expect(RealtimeCodec.parse(#"{"type":"error"}"#)
           == .serverError("error del servidor"),
           "parse: error sin cuerpo usa el fallback")
    expect(RealtimeCodec.parse(#"{"type":"error","error":{}}"#)
           == .serverError("error del servidor"),
           "parse: error sin message usa el fallback")
}

@MainActor func testRealtimeSessionUpdate() {
    let up = json(RealtimeCodec.sessionUpdate(
        instructions: "hola",
        tools: [ToolSpec.delegate, .resolveApproval],
        voice: .marin,
        speed: 1.0,
        turnDetection: .serverVAD(silenceMs: 700)))
    expectEq(up["type"] as? String ?? "", "session.update", "update: tipo")
    let s = up["session"] as? [String: Any] ?? [:]
    expectEq(s["type"] as? String ?? "", "realtime", "update: session.type GA")
    expectEq(s["instructions"] as? String ?? "", "hola", "update: instructions")
    expectEq((s["output_modalities"] as? [String]) ?? [], ["audio"],
             "update: output_modalities audio")
    let audio = s["audio"] as? [String: Any] ?? [:]
    let input = audio["input"] as? [String: Any] ?? [:]
    let format = input["format"] as? [String: Any] ?? [:]
    expectEq(format["type"] as? String ?? "", "audio/pcm", "update: pcm de entrada")
    expectEq(format["rate"] as? Int ?? 0, 24000, "update: 24 kHz de entrada")
    let tx = input["transcription"] as? [String: Any] ?? [:]
    expectEq(tx["model"] as? String ?? "", "gpt-4o-mini-transcribe",
             "update: transcribe mini")
    expectEq(tx["language"] as? String ?? "", "es", "update: idioma es")
    let nr = input["noise_reduction"] as? [String: Any] ?? [:]
    expectEq(nr["type"] as? String ?? "", "near_field", "update: near_field")
    let vad = input["turn_detection"] as? [String: Any] ?? [:]
    expectEq(vad["type"] as? String ?? "", "server_vad", "update: VAD del server")
    expectEq(vad["silence_duration_ms"] as? Int ?? 0, 700,
             "update: 700 ms de silencio")
    let output = audio["output"] as? [String: Any] ?? [:]
    let outFmt = output["format"] as? [String: Any] ?? [:]
    expectEq(outFmt["rate"] as? Int ?? 0, 24000, "update: 24 kHz de salida")
    expectEq(output["voice"] as? String ?? "", "marin", "update: voz marin")
    expectEq(output["speed"] as? Double ?? 0, 1.0, "update: speed viaja")
    let tools = s["tools"] as? [[String: Any]] ?? []
    expectEq(tools.count, 2, "update: delegate + resolve_approval")
    expectEq(tools.first?["name"] as? String ?? "", "delegate",
             "update: tool PLANO cuando hay especialista")
    expect(tools.first?["function"] == nil,
           "update: el tool no va anidado como en chat completions")
    expectEq(tools.last?["name"] as? String ?? "", "resolve_approval",
             "update: segundo tool es approval")

    let solo = json(RealtimeCodec.sessionUpdate(
        instructions: "hola",
        tools: [],
        voice: .marin,
        speed: 1.0,
        turnDetection: .serverVAD(silenceMs: 700)))
    let s2 = solo["session"] as? [String: Any] ?? [:]
    expect(s2["tools"] == nil, "update: sin especialista no viaja el tool")

    let muted = json(RealtimeCodec.sessionUpdate(
        instructions: "x",
        tools: [],
        voice: nil,
        speed: 1.25,
        turnDetection: .semanticVAD(eagerness: .auto)))
    let out2 = ((muted["session"] as? [String: Any])?["audio"] as? [String: Any])?["output"]
        as? [String: Any] ?? [:]
    expect(out2["voice"] == nil, "update: voice nil omite la clave")
    expectEq(out2["speed"] as? Double ?? 0, 1.25, "update: speed siempre viaja")
    let vad2 = (((muted["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"]
                as? [String: Any])?["turn_detection"] as? [String: Any] ?? [:]
    expectEq(vad2["type"] as? String ?? "", "semantic_vad", "update: semantic_vad")
    expectEq(vad2["eagerness"] as? String ?? "", "auto", "update: eagerness auto")
    expect(vad2["silence_duration_ms"] == nil,
           "update: semantic_vad no lleva silence_ms")

    let quoted = json(RealtimeCodec.sessionUpdate(
        instructions: #"dijo "hola" y ñoño"#,
        tools: [ToolSpec.delegate],
        voice: .cedar,
        speed: 0.25,
        turnDetection: .semanticVAD(eagerness: .low)))
    let s3 = quoted["session"] as? [String: Any] ?? [:]
    expectEq(s3["instructions"] as? String ?? "", #"dijo "hola" y ñoño"#,
             "update: unicode y comillas en instructions")
    let voice3 = ((s3["audio"] as? [String: Any])?["output"] as? [String: Any])?["voice"]
        as? String ?? ""
    expectEq(voice3, "cedar", "update: voz inyectada")
    let tools3 = s3["tools"] as? [[String: Any]] ?? []
    expectEq(tools3.count, 1, "update: un tool no inventa el segundo")
    expect((tools3.first?["parameters"] as? [String: Any]) != nil,
           "update: parameters viajan en el tool plano")
}

@MainActor func testRealtimeSeed() {
    expect(RealtimeCodec.seed(from: []) == nil,
           "seed: sin historia no hay contexto")
    let hist: [Turn] = [
        Turn(role: .user, content: "hola"),
        Turn(role: .assistant, content: "¿qué tal?"),
    ]
    let seed = RealtimeCodec.seed(from: hist) ?? ""
    expect(seed.contains("Usuario: hola"), "seed: rol usuario legible")
    expect(seed.contains("Companion: ¿qué tal?"), "seed: rol assistant legible")
    let larga = [Turn(role: .user, content: String(repeating: "a", count: 500))]
    expect((RealtimeCodec.seed(from: larga) ?? "").count < 260,
           "seed: cada turno viaja recortado")
    expectEq(RealtimeCodec.seed(from: larga) ?? "",
             "Usuario: " + String(repeating: "a", count: RealtimeCodec.seedChars),
             "seed: tope exacto de seedChars")

    let many = (1...8).map { Turn(role: .user, content: "t\($0)") }
    let window = RealtimeCodec.seed(from: many) ?? ""
    expect(!window.contains("t1") && !window.contains("t2"),
           "seed: se caen los turnos fuera de la ventana")
    expect(window.contains("t3") && window.contains("t8"),
           "seed: conserva los últimos seedTurns")
    expectEq(window.split(separator: "\n").count, RealtimeCodec.seedTurns,
             "seed: default 6 turnos")

    let sys = RealtimeCodec.seed(from: [Turn(role: .system, content: "nota")]) ?? ""
    expectEq(sys, "Companion: nota", "seed: system no es Usuario")
    expectEq(RealtimeCodec.seed(from: hist, turns: 1), "Companion: ¿qué tal?",
             "seed: turns recorta al último")
    expectEq(RealtimeCodec.seed(from: hist, turns: 0), "",
             "seed: turns 0 con historia no es nil — cadena vacía")
    let emoji = [Turn(role: .user, content: "hola 👋 café")]
    expectEq(RealtimeCodec.seed(from: emoji), "Usuario: hola 👋 café",
             "seed: unicode no se corrompe")
    let huge = [Turn(role: .user, content: String(repeating: "b", count: 10_000))]
    expectEq((RealtimeCodec.seed(from: huge) ?? "").count,
             "Usuario: ".count + RealtimeCodec.seedChars,
             "seed: 10k chars se recortan al tope")
}

@MainActor func testRealtimeSystemItem() {
    let item = json(RealtimeCodec.systemItem("el encargo terminó"))
    expectEq(item["type"] as? String ?? "", "conversation.item.create",
             "anuncio: evento de item")
    let inner = item["item"] as? [String: Any] ?? [:]
    expectEq(inner["type"] as? String ?? "", "message", "anuncio: item.message")
    expectEq(inner["role"] as? String ?? "", "system",
             "anuncio: entra como sistema, no como usuario")
    let content = inner["content"] as? [[String: Any]] ?? []
    expectEq(content.first?["type"] as? String ?? "", "input_text",
             "anuncio: content input_text")
    expectEq(content.first?["text"] as? String ?? "", "el encargo terminó",
             "anuncio: el texto viaja intacto")
    let quoted = json(RealtimeCodec.systemItem(#"dijo "listo" 👋"#))
    let qContent = ((quoted["item"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    expectEq(qContent.first?["text"] as? String ?? "", #"dijo "listo" 👋"#,
             "anuncio: unicode y comillas")
    let empty = json(RealtimeCodec.systemItem(""))
    let eContent = ((empty["item"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    expectEq(eContent.first?["text"] as? String ?? "missing", "",
             "anuncio: texto vacío viaja")
}

@MainActor func testApprovalTool() {
    let t = json(RealtimeCodec.approvalToolJSON())
    expectEq(t["name"] as? String ?? "", "resolve_approval", "tool: nombre")
    expectEq(t["type"] as? String ?? "", "function", "tool: type function")
    expect(t["function"] == nil, "tool: plano, como exige Realtime")
    expectEq(RealtimeCodec.approvalToolJSON(),
             ToolSpec.resolveApproval.encodeRealtime(),
             "tool: approvalToolJSON es encodeRealtime de resolveApproval")
    let params = t["parameters"] as? [String: Any] ?? [:]
    expectEq((params["required"] as? [String]) ?? [], ["approved"],
             "tool: required approved")
    let approved = ((params["properties"] as? [String: Any])?["approved"]) as? [String: Any] ?? [:]
    expectEq(approved["type"] as? String ?? "", "boolean", "tool: approved boolean")
    expectEq(approved["description"] as? String ?? "", "true si el usuario lo autorizó",
             "tool: wording de approved")

    let up = json(RealtimeCodec.sessionUpdate(
        instructions: "x",
        tools: [ToolSpec.delegate, .resolveApproval],
        voice: .marin,
        speed: 1.0,
        turnDetection: .serverVAD(silenceMs: 700)))
    let tools = ((up["session"] as? [String: Any])?["tools"]) as? [[String: Any]] ?? []
    expectEq(tools.count, 2, "sesión: delegate + resolve_approval con especialista")

    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":true}"#) == true,
           "decisión: approved true")
    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":false}"#) == false,
           "decisión: approved false")
    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":"si"}"#) == nil,
           "decisión: un string no es un booleano — no se adivina un permiso")
    expect(RealtimeCodec.approvalDecision(fromArguments: "basura") == nil,
           "decisión: JSON roto no concede nada")
    expect(RealtimeCodec.approvalDecision(fromArguments: "") == nil,
           "decisión: vacío no concede")
    expect(RealtimeCodec.approvalDecision(fromArguments: "{}") == nil,
           "decisión: sin approved no concede")
    expect(RealtimeCodec.approvalDecision(fromArguments: "[]") == nil,
           "decisión: un array no es decisión")
    expect(RealtimeCodec.approvalDecision(fromArguments: "null") == nil,
           "decisión: null no concede")
    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":1}"#) == nil,
           "decisión: JSON 1 no es un booleano — no concede")
    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":0}"#) == nil,
           "decisión: JSON 0 no es un deny — no se adivina")
    expect(RealtimeCodec.approvalDecision(fromArguments: #"{"approved":1.0}"#) == nil,
           "decisión: JSON 1.0 no concede")
}

@MainActor func testRealtimeControlFrames() {
    expectEq(RealtimeCodec.model, "gpt-realtime", "url: modelo GA")
    expectEq(RealtimeCodec.seedTurns, 6, "seed: ventana default")
    expectEq(RealtimeCodec.seedChars, 200, "seed: recorte default")
    expectEq(RealtimeCodec.url()?.absoluteString ?? "",
             "wss://api.openai.com/v1/realtime?model=gpt-realtime",
             "url: default")
    expectEq(RealtimeCodec.url(model: "gpt-4o-realtime-preview")?.absoluteString ?? "",
             "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview",
             "url: model inyectado")

    expectEq(json(RealtimeCodec.commitAudio())["type"] as? String ?? "",
             "input_audio_buffer.commit", "commit: type")
    expectEq(json(RealtimeCodec.clearAudio())["type"] as? String ?? "",
             "input_audio_buffer.clear", "clear: type")
    expectEq(json(RealtimeCodec.responseCreate())["type"] as? String ?? "",
             "response.create", "create: type")
    expectEq(json(RealtimeCodec.responseCancel())["type"] as? String ?? "",
             "response.cancel", "cancel: type")

    let out = json(RealtimeCodec.functionOutput(callId: "c1", output: #"{"ok":true}"#))
    expectEq(out["type"] as? String ?? "", "conversation.item.create",
             "fn out: item.create")
    let item = out["item"] as? [String: Any] ?? [:]
    expectEq(item["type"] as? String ?? "", "function_call_output",
             "fn out: function_call_output")
    expectEq(item["call_id"] as? String ?? "", "c1", "fn out: call_id")
    expectEq(item["output"] as? String ?? "", #"{"ok":true}"#, "fn out: output")

    let empty = json(RealtimeCodec.functionOutput(callId: "", output: ""))
    let emptyItem = empty["item"] as? [String: Any] ?? [:]
    expectEq(emptyItem["call_id"] as? String ?? "missing", "", "fn out: call_id vacío")
    expectEq(emptyItem["output"] as? String ?? "missing", "", "fn out: output vacío")

    let rt = json(ToolSpec.delegate.encodeRealtime())
    expectEq(rt["name"] as? String ?? "", "delegate", "realtime tool: name arriba")
    expect(rt["function"] == nil, "realtime tool: sin nido function")
    expectEq(rt["type"] as? String ?? "", "function", "realtime tool: type")
}

@MainActor func testRealtimeAppendAudio() {
    let pcm = Data("hola".utf8)
    let frame = json(RealtimeCodec.appendAudio(pcm))
    expectEq(frame["type"] as? String ?? "", "input_audio_buffer.append",
             "append: type")
    expectEq(frame["audio"] as? String ?? "", pcm.base64EncodedString(),
             "append: audio es base64 de hola")
    expectEq(Set(frame.keys), Set(["type", "audio"]),
             "append: solo type y audio")

    let empty = json(RealtimeCodec.appendAudio(Data()))
    expectEq(empty["type"] as? String ?? "", "input_audio_buffer.append",
             "append: vacío aún es append")
    expectEq(empty["audio"] as? String ?? "missing", "",
             "append: data vacía viaja como audio vacío")

    let binary = Data([0x00, 0xFF, 0x7F, 0x80])
    expectEq(
        json(RealtimeCodec.appendAudio(binary))["audio"] as? String ?? "",
        binary.base64EncodedString(),
        "append: bytes binarios se base64-ean")

    let large = Data(repeating: 0xAB, count: 10_000)
    expectEq(
        json(RealtimeCodec.appendAudio(large))["audio"] as? String ?? "",
        large.base64EncodedString(),
        "append: 10k bytes caben")
}

private func json(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!)) as? [String: Any] ?? [:]
}
