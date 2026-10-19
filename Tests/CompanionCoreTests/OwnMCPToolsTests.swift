import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Nombres de las herramientas de los servidores MCP propios: dos servidores
// con el mismo nombre combinado no pueden colisionar, y un servidor con
// muchas herramientas no llena el contexto del modelo.

@Test func ownMCPToolNamesStayUniqueWhenTheyCollide() {
    // "mcp_a__b__c" sale de dos maneras distintas: servidor "a" + herramienta
    // "b__c", o servidor "a__b" + herramienta "c".
    let first = OwnMCPTools.Listed(
        server: MCPServerConfig(label: "a", url: "https://a.dev/mcp"),
        tools: [OwnMCPTools.RemoteTool(name: "b__c", description: "", inputSchemaJSON: nil)])
    let second = OwnMCPTools.Listed(
        server: MCPServerConfig(label: "a__b", url: "https://ab.dev/mcp"),
        tools: [OwnMCPTools.RemoteTool(name: "c", description: "", inputSchemaJSON: nil)])

    let names = OwnMCPTools.catalog([first, second]).map(\.name)
    expectEq(names.count, 2, "colision: ambas herramientas siguen listadas")
    expectEq(Set(names).count, 2, "colision: los nombres salen distintos")
    expect(names.allSatisfy { $0.hasPrefix(OwnMCPTools.prefix) }, "colision: prefijo de espacio propio")
}

@Test func ownMCPToolCountIsCappedPerServerAndInAll() {
    let many = (0..<40).map {
        OwnMCPTools.RemoteTool(name: "t\($0)", description: "", inputSchemaJSON: nil)
    }
    let server = MCPServerConfig(label: "docs", url: "https://docs.dev/mcp")
    let one = OwnMCPTools.catalog([OwnMCPTools.Listed(server: server, tools: many)])
    expectEq(one.count, OwnMCPTools.maxToolsPerServer, "tope: por servidor")

    let others = (0..<3).map {
        OwnMCPTools.Listed(
            server: MCPServerConfig(label: "s\($0)", url: "https://s\($0).dev/mcp"), tools: many)
    }
    let all = OwnMCPTools.catalog(others)
    expectEq(all.count, OwnMCPTools.maxTools, "tope: total de herramientas propias")
}
