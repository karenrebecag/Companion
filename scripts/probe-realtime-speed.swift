// Live probe for task 0 / PR-1 of docs/specs/velocidad-de-voz-por-conversacion.md (section 4).
// Run: OPENAI_API_KEY=... swift scripts/probe-realtime-speed.swift
//
// It spends real API credits. Event and field names mirror what the app sends
// (Sources/CompanionCore/Voice/RealtimeCodec.swift), so a PASS here means the
// app's own wire format is accepted, not a look-alike.
import Foundation

let model = "gpt-realtime"
let voice = "marin"
let toolName = "set_speech_speed"
let bytesPerSecond = 24_000.0 * 2.0  // pcm16 mono at 24 kHz
// Hard cap so a stuck socket can never hang the caller.
let globalTimeoutSeconds = 300.0
let stepTimeoutSeconds = 45.0
let ratioLimit = 0.85

// Unbuffered so a partial report survives the global timeout.
setvbuf(stdout, nil, _IONBF, 0)

func emit(_ line: String = "") { print(line) }

// MARK: wire format (mirrors RealtimeCodec)

func encodeJSON(_ obj: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let text = String(data: data, encoding: .utf8) else { return "{}" }
    return text
}

let instructions = """
Eres un lector. Repite en voz alta exactamente el texto que el usuario te da, \
sin agregar ni quitar nada. Si el usuario te pide hablar mas rapido, llama a \
la herramienta set_speech_speed.
"""

func sessionUpdate(speed: Double) -> String {
    let tool: [String: Any] = [
        "type": "function",
        "name": toolName,
        "description": "Cambia la velocidad de la voz para esta conversacion.",
        "parameters": [
            "type": "object",
            "properties": [
                "speed": ["type": "number", "description": "Factor de velocidad, 1.0 es normal."]
            ],
            "required": ["speed"],
        ] as [String: Any],
    ]
    let session: [String: Any] = [
        "type": "realtime",
        "instructions": instructions,
        "output_modalities": ["audio"],
        "audio": [
            "input": [
                "format": ["type": "audio/pcm", "rate": 24000],
                "noise_reduction": ["type": "near_field"],
                "turn_detection": NSNull(),
            ] as [String: Any],
            "output": [
                "format": ["type": "audio/pcm", "rate": 24000],
                "speed": wireSpeed(speed),
                "voice": voice,
            ] as [String: Any],
        ] as [String: Any],
        "tools": [tool],
    ]
    return encodeJSON(["type": "session.update", "session": session])
}

// JSONSerialization writes a Double like 0.8 as 0.80000000000000004, and the
// server rejects more than 16 decimal places (first run, 2026-10-01). A
// Decimal built from two decimals serializes as the short literal.
func wireSpeed(_ speed: Double) -> Decimal {
    Decimal(string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), speed)) ?? 1
}

func speedUpdate(_ speed: Double) -> String {
    encodeJSON([
        "type": "session.update",
        "session": ["type": "realtime", "audio": ["output": ["speed": wireSpeed(speed)]]],
    ])
}

func userTextItem(_ text: String) -> String {
    encodeJSON([
        "type": "conversation.item.create",
        "item": [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": text]],
        ],
    ])
}

func functionOutput(callId: String, output: String) -> String {
    encodeJSON([
        "type": "conversation.item.create",
        "item": ["type": "function_call_output", "call_id": callId, "output": output],
    ])
}

let responseCreate = encodeJSON(["type": "response.create"])
let responseCancel = encodeJSON(["type": "response.cancel"])

// MARK: event log

struct Ev {
    let type: String
    var audioBytes = 0
    var text = ""
    var error = ""
    var speed: Double?
    var callName = ""
    var callId = ""
}

final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Ev] = []
    private var closed: String?

    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    func slice(from mark: Int) -> [Ev] {
        lock.lock(); defer { lock.unlock() }
        return Array(events[min(mark, events.count)...])
    }
    func append(_ ev: Ev) { lock.lock(); events.append(ev); lock.unlock() }
    func close(_ reason: String) { lock.lock(); closed = closed ?? reason; lock.unlock() }
    var closeReason: String? { lock.lock(); defer { lock.unlock() }; return closed }
    var allTypes: [String] {
        lock.lock(); defer { lock.unlock() }
        var seen = Set<String>(); var ordered: [String] = []
        for e in events where seen.insert(e.type).inserted { ordered.append(e.type) }
        return ordered
    }
}

func parseEvent(_ text: String) -> Ev? {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = obj["type"] as? String else { return nil }
    var ev = Ev(type: type)
    switch type {
    case "response.output_audio.delta":
        ev.audioBytes = (obj["delta"] as? String).flatMap { Data(base64Encoded: $0)?.count } ?? 0
    case "response.output_audio_transcript.delta":
        ev.text = obj["delta"] as? String ?? ""
    case "response.output_audio_transcript.done":
        ev.text = obj["transcript"] as? String ?? ""
    case "session.updated":
        let output = ((obj["session"] as? [String: Any])?["audio"] as? [String: Any])?["output"]
        ev.speed = (output as? [String: Any])?["speed"] as? Double
    case "response.function_call_arguments.done":
        ev.callName = obj["name"] as? String ?? ""
        ev.callId = obj["call_id"] as? String ?? ""
        ev.text = obj["arguments"] as? String ?? ""
    case "error":
        let err = obj["error"] as? [String: Any] ?? [:]
        // Literal message plus code/param, since the spec asks for the error as received.
        ev.error = [err["message"], err["code"], err["param"]]
            .compactMap { $0 as? String }.joined(separator: " | ")
        if ev.error.isEmpty { ev.error = "(error event without message)" }
    default: break
    }
    return ev
}

// MARK: socket

final class Socket: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    let log = Log()

    init(key: String) {
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        task = URLSession(configuration: .ephemeral).webSocketTask(with: request)
    }

    func start() {
        task.resume()
        Task { [self] in
            while true {
                do {
                    let message = try await task.receive()
                    if case .string(let text) = message, let ev = parseEvent(text) { log.append(ev) }
                } catch {
                    // Status only: the error's userInfo may echo the request, which carries the key.
                    let status = (task.response as? HTTPURLResponse)?.statusCode
                    log.close("socket closed" + (status.map { " (HTTP \($0))" } ?? ""))
                    return
                }
            }
        }
    }

    func send(_ json: String) async {
        do { try await task.send(.string(json)) }
        catch { log.close("send failed") }
    }

    func wait(from mark: Int, _ until: ([Ev]) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(stepTimeoutSeconds)
        while Date() < deadline {
            if until(log.slice(from: mark)) { return true }
            if log.closeReason != nil { return false }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }
}

// MARK: measurements

struct Run {
    let label: String
    let seconds: Double
    let chars: Int
    let transcript: String
    let errors: [String]
    var secPerChar: Double? { chars > 0 && seconds > 0 ? seconds / Double(chars) : nil }
}

func measure(_ label: String, _ evs: [Ev]) -> Run {
    let bytes = evs.reduce(0) { $0 + $1.audioBytes }
    let done = evs.last { $0.type == "response.output_audio_transcript.done" }?.text
    let transcript = (done?.isEmpty == false ? done : nil)
        ?? evs.filter { $0.type == "response.output_audio_transcript.delta" }.map(\.text).joined()
    return Run(label: label, seconds: Double(bytes) / bytesPerSecond, chars: transcript.count,
               transcript: transcript, errors: evs.filter { $0.type == "error" }.map(\.error))
}

func has(_ evs: [Ev], _ type: String) -> Bool { evs.contains { $0.type == type } }
func fmt(_ x: Double?) -> String { x.map { String(format: "%.4f", $0) } ?? "n/a" }

// MARK: probe

guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
    emit("OPENAI_API_KEY is not set")
    exit(2)
}

DispatchQueue.global().asyncAfter(deadline: .now() + globalTimeoutSeconds) {
    emit("")
    emit("ABORT: global timeout of \(Int(globalTimeoutSeconds))s reached; report above is partial")
    exit(2)
}

let fixedText = "Lee exactamente esto: Manana a las nueve tengo junta con el equipo de diseno, "
    + "despues voy a comer con Laura y por la tarde reviso los pendientes del proyecto."

var runs: [Run] = []
var infoLines: [String] = []
var failures: [String] = []
var p1 = false, p2 = false, p3 = false
var p1Why = "", p2Why = "", p3Why = ""

emit("Realtime speed probe")
emit("model: \(model)")
emit("voice: \(voice)")
emit("date: \(ISO8601DateFormatter().string(from: Date()))")
emit("")

let socket = Socket(key: key)
socket.start()
let log = socket.log

func textTurn(_ label: String, _ text: String) async -> Run {
    let mark = log.count
    await socket.send(userTextItem(text))
    await socket.send(responseCreate)
    _ = await socket.wait(from: mark) { has($0, "response.done") || has($0, "error") }
    let run = measure(label, log.slice(from: mark))
    return run
}

func updateSpeed(_ speed: Double) async -> (reflected: Double?, errors: [String], gotUpdated: Bool) {
    let mark = log.count
    await socket.send(speedUpdate(speed))
    _ = await socket.wait(from: mark) { has($0, "session.updated") || has($0, "error") }
    let evs = log.slice(from: mark)
    return (evs.last { $0.type == "session.updated" }?.speed,
            evs.filter { $0.type == "error" }.map(\.error),
            has(evs, "session.updated"))
}

// Step 1: connect, session.update at speed 1.0, turn_detection null.
let step1Mark = log.count
await socket.send(sessionUpdate(speed: 1.0))
let step1Ok = await socket.wait(from: 0) { has($0, "session.updated") || has($0, "error") }
let step1Errors = log.slice(from: step1Mark).filter { $0.type == "error" }.map(\.error)
emit("step 1 (connect + session.update speed 1.0): "
    + (step1Ok && step1Errors.isEmpty ? "ok" : "problem \(step1Errors) \(log.closeReason ?? "")"))

// Step 2: baseline turn at 1.0.
let run2 = await textTurn("step 2 (speed 1.0)", fixedText)
runs.append(run2)

// Step 3: mid-session speed update to 1.4.
let upd = await updateSpeed(1.4)
emit("step 3 (speedUpdate 1.4): session.updated=\(upd.gotUpdated) reflected speed=\(upd.reflected.map { "\($0)" } ?? "n/a") errors=\(upd.errors)")
p1 = upd.errors.isEmpty && upd.gotUpdated && upd.reflected == 1.4
p1Why = p1 ? "session.updated reflects 1.4 and no error"
    : "errors=\(upd.errors) session.updated=\(upd.gotUpdated) reflected=\(upd.reflected.map { "\($0)" } ?? "n/a")"

// Step 4: same turn after the update.
let run4 = await textTurn("step 4 (speed 1.4)", fixedText)
runs.append(run4)
if let a = run2.secPerChar, let b = run4.secPerChar {
    let ratio = b / a
    p2 = ratio <= ratioLimit
    p2Why = String(format: "step4/step2 = %.3f (limit %.2f)", ratio, ratioLimit)
} else {
    p2Why = "missing audio or transcript in step 2 or 4"
}

// Step 5: tool route. The app answers the call at once, waits for response.done,
// applies the new speed, then asks for the spoken confirmation.
let step5Mark = log.count
await socket.send(userTextItem("Habla mas rapido, por favor. Usa la herramienta \(toolName) con speed 1.3."))
await socket.send(responseCreate)
let gotCall = await socket.wait(from: step5Mark) {
    $0.contains { $0.type == "response.function_call_arguments.done" } || has($0, "error")
}
let call = log.slice(from: step5Mark).first { $0.type == "response.function_call_arguments.done" }
var step5Errors: [String] = []
var run5: Run?
if gotCall, let call {
    emit("step 5: tool call \(call.callName) arguments=\(call.text)")
    await socket.send(functionOutput(callId: call.callId, output: "{\"speed\":0.8}"))
    _ = await socket.wait(from: step5Mark) { has($0, "response.done") || has($0, "error") }
    let upd5 = await updateSpeed(0.8)
    step5Errors += upd5.errors
    let mark = log.count
    await socket.send(responseCreate)
    _ = await socket.wait(from: mark) { has($0, "response.done") || has($0, "error") }
    let evs = log.slice(from: mark)
    step5Errors += evs.filter { $0.type == "error" }.map(\.error)
    let r = measure("step 5 (tool route, final reply at 0.8)", evs)
    runs.append(r)
    run5 = r
    p3 = step5Errors.isEmpty && r.seconds > 0
    p3Why = "errors=\(step5Errors) audio=\(fmt(r.seconds))s"
} else {
    step5Errors = log.slice(from: step5Mark).filter { $0.type == "error" }.map(\.error)
    p3Why = "model never called \(toolName); errors=\(step5Errors) \(log.closeReason ?? "")"
}

// Step 6: informational only, never affects the exit code.
let longText = "Lee exactamente esto: " + String(repeating: "El proyecto avanza segun lo planeado y el equipo sigue revisando los detalles. ", count: 4)

let midMark = log.count
await socket.send(userTextItem(longText))
await socket.send(responseCreate)
_ = await socket.wait(from: midMark) { $0.contains { $0.audioBytes > 0 } }
let midUpd = await updateSpeed(1.2)
_ = await socket.wait(from: midMark) { has($0, "response.done") }
infoLines.append("6a update mid-response (1.2): session.updated=\(midUpd.gotUpdated) reflected=\(midUpd.reflected.map { "\($0)" } ?? "n/a") errors=\(midUpd.errors)")
runs.append(measure("step 6a (update mid-response, informational)", log.slice(from: midMark)))

let cancelMark = log.count
await socket.send(userTextItem(longText))
await socket.send(responseCreate)
_ = await socket.wait(from: cancelMark) { $0.contains { $0.audioBytes > 0 } }
await socket.send(responseCancel)
_ = await socket.wait(from: cancelMark) { has($0, "response.done") }
let cancelErrors = log.slice(from: cancelMark).filter { $0.type == "error" }.map(\.error)
let afterCancel = await updateSpeed(1.3)
infoLines.append("6b update after response.cancel (1.3): cancel errors=\(cancelErrors) session.updated=\(afterCancel.gotUpdated) reflected=\(afterCancel.reflected.map { "\($0)" } ?? "n/a") errors=\(afterCancel.errors)")

let high = await updateSpeed(1.6)
infoLines.append("6c speed 1.6: session.updated=\(high.gotUpdated) reflected=\(high.reflected.map { "\($0)" } ?? "n/a") errors=\(high.errors)")

socket.task.cancel(with: .normalClosure, reason: nil)

// MARK: report

emit("")
emit("event types received: " + log.allTypes.joined(separator: ", "))
emit("")
let allErrors = runs.flatMap(\.errors) + step1Errors + step5Errors
emit("error messages (literal):")
if allErrors.isEmpty && upd.errors.isEmpty && midUpd.errors.isEmpty
    && afterCancel.errors.isEmpty && high.errors.isEmpty && cancelErrors.isEmpty {
    emit("  (none)")
} else {
    for e in Set(allErrors + upd.errors + midUpd.errors + afterCancel.errors + high.errors + cancelErrors).sorted() {
        emit("  \(e)")
    }
}
emit("")
emit("audio seconds per character (pcm16 24 kHz mono):")
for r in runs {
    emit("  \(r.label): \(fmt(r.secPerChar)) s/char  (\(fmt(r.seconds)) s audio, \(r.chars) chars)")
    emit("    transcript: \(r.transcript)")
}
emit("")
emit("informational (step 6):")
infoLines.forEach { emit("  \($0)") }
emit("")
emit("criteria:")
emit("  P1 \(p1 ? "PASS" : "FAIL"): \(p1Why)")
emit("  P2 \(p2 ? "PASS" : "FAIL"): \(p2Why)")
emit("  P3 \(p3 ? "PASS" : "FAIL"): \(p3Why)")
if !p1 { failures.append("P1") }
if !p2 { failures.append("P2") }
if !p3 { failures.append("P3") }
emit("")
emit(failures.isEmpty ? "RESULT: all criteria PASS" : "RESULT: FAIL (\(failures.joined(separator: ", ")))")
exit(failures.isEmpty ? 0 : 1)
