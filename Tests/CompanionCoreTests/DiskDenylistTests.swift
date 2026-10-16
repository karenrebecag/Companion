import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The disk is open (ADR 013); this is the list that stays closed. One row per
// path, so a name that falls off the list names itself in the failure.

private let home = "/Users/k"

private func validator(roots: [PathValidator.Root] = []) -> PathValidator {
    PathValidator(workdir: nil, extraRoots: roots, wholeDisk: true, home: home)
}

@Test func theClosedListHoldsOnePathPerRow() {
    let closed = [
        "/System/Library/x", "/Library/Keychains/System.keychain", "/usr/bin/true", "/bin/sh", "/sbin/mount",
        "/private/etc/hosts", "/etc/hosts", "/private/var/db/dslocal/x",
        "\(home)/Library/Keychains/login.keychain-db", "\(home)/.ssh/id_rsa", "\(home)/.aws/credentials",
        "\(home)/.config/gcloud/credentials.db", "\(home)/.config/gh/hosts.yml", "\(home)/.config/git/credentials",
        "\(home)/.git-credentials", "\(home)/.netrc", "\(home)/.npmrc", "\(home)/.pypirc",
        "\(home)/.docker/config.json", "\(home)/.kube/config", "\(home)/.gnupg/private-keys-v1.d/k",
        "\(home)/.azure/accessTokens.json", "\(home)/.config/op/config", "\(home)/.terraform.d/credentials.tfrc.json",
        "\(home)/.zsh_history", "\(home)/.bash_history",
        "\(home)/Library/Application Support/Google/Chrome/Default/Cookies",
        "\(home)/Library/Application Support/BraveSoftware/x", "\(home)/Library/Application Support/Microsoft Edge/x",
        "\(home)/Library/Application Support/Firefox/Profiles/x", "\(home)/Library/Application Support/Arc/x",
        "\(home)/Library/Application Support/Comet/x", "\(home)/Library/Application Support/Perplexity/x",
        "\(home)/Library/Cookies/Cookies.binarycookies", "\(home)/Library/Safari/History.db",
        "\(home)/Library/Mail/V10/x", "\(home)/Library/Messages/chat.db",
        "\(home)/Library/Containers/com.apple.mail/x", "\(home)/Library/Group Containers/group.x/y",
        "\(home)/Library/Application Support/Companion/memory/x.md",
        "\(home)/LIBRARY/SAFARI/History.db", "\(home)/.SSH/id_rsa",
        "\(home)/.zshrc", "\(home)/.claude/.credentials.json", "\(home)/.config/vercel/auth.json",
        "\(home)/.cargo/credentials.toml", "\(home)/.vault-token", "\(home)/code/.git/config",
        "\(home)/Library/Application Support/Slack/x", "\(home)/Library/Application Support/Discord/x",
        "\(home)/Library/Application Support/Signal/x",
        "\(home)/code/app/.env", "/tmp/.env", "\(home)/code/.env.local", "/srv/app/.ENV.production",
    ]
    let open = validator()
    for path in closed {
        expect(!open.isAllowed(path), "debe negar \(path)")
        expect(!open.isAllowed(path, forWrite: true), "debe negar escribir \(path)")
    }
}

@Test func ordinaryPathsStayOpen() {
    let open = validator()
    for path in [
        "\(home)/Desktop/x.txt", "\(home)/Documents/env.md", "/srv/app/.envrc", "\(home)/code/environment.txt",
        "\(home)/Library/Application Support/Code/x", "/tmp/x", "/Volumes/Disk/x",
    ] {
        expect(open.isAllowed(path), "debe permitir \(path)")
    }
}

@Test func anAppRootNeverOpensAnotherClosedPath() {
    // A root exempts Companion's own folder from the container rule and nothing else.
    let inside = [
        PathValidator.Root(path: "\(home)/.ssh/keys", writable: true),
        PathValidator.Root(path: "\(home)/code/.env", writable: true),
        PathValidator.Root(path: "/etc/skills", writable: true),
    ]
    let open = validator(roots: inside)
    for path in ["\(home)/.ssh/keys/id", "\(home)/code/.env", "/etc/skills/x"] {
        expect(!open.isAllowed(path), "una raíz no abre \(path)")
    }
    let own = [PathValidator.Root(path: "\(home)/Library/Application Support/Companion/memory", writable: true)]
    expect(validator(roots: own).isAllowed("\(home)/Library/Application Support/Companion/memory/a.md"),
           "la memoria propia sigue abierta")
    expect(!validator(roots: own).isAllowed("\(home)/Library/Application Support/Companion/bridge.token"),
           "el resto del contenedor sigue cerrado")
}

// `~` is the home folder for every file tool. Read as a plain name it became a
// folder called "~" under the working folder, and the model took the empty
// answer for "the file is not there".
@Test func tildeNamesTheHomeFolderForEveryFileTool() {
    let open = validator()
    expectEq(open.absolute("~/Desktop/x.md"), "\(home)/Desktop/x.md", "~/ es la carpeta de inicio")
    expectEq(open.absolute("~"), home, "~ solo es la carpeta de inicio")
    expect(open.isAllowed("~/Desktop/x.md"), "~/ se resuelve antes de validar")

    let scoped = PathValidator(workdir: "\(home)/Projects/app", extraRoots: [], wholeDisk: false, home: home)
    expect(!scoped.isAllowed("~/Desktop/x.md"), "~/ fuera del workdir no entra por estar dentro del workdir")
    expectEq(scoped.absolute("Desktop/x.md"), "\(home)/Projects/app/Desktop/x.md",
             "relativa: contra el workdir, igual que en el resto de las tools")
}

@Test func relativePathsResolveAgainstHomeWhenNoWorkdir() {
    expectEq(validator().absolute("Desktop/x.md"), "\(home)/Desktop/x.md",
             "sin workdir y con el disco abierto, relativa = carpeta de inicio")
}

// Relative paths read the same way in every file tool. With the disk open (the
// production setting) the workdir bounds nothing, so a relative path is taken
// from the home folder, as open_file and the chips always did.
@Test func aRelativePathResolvesTheSameForEveryFileTool() throws {
    let disk = PathValidator(workdir: "\(home)/Projects/app", extraRoots: [], wholeDisk: true, home: home)
    let want = "\(home)/Desktop/x.md"
    expectEq(disk.absolute("Desktop/x.md"), want, "especialista: relativa contra la carpeta de inicio")
    expectEq(FileChip.expanded("Desktop/x.md", home: home), want, "chip: la misma ruta")

    let fake = FileManager.default.temporaryDirectory
        .appendingPathComponent("qa4-home-\(UUID().uuidString)", isDirectory: true)
    let file = fake.appendingPathComponent("Desktop/x.md")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: file.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: fake) }
    let opened = try ParentToolPolicy.homePath("Desktop/x.md", home: fake)
    expectEq(opened.resolvingSymlinksInPath().path, file.resolvingSymlinksInPath().path,
             "open_file: la misma ruta desde la carpeta de inicio")
}
