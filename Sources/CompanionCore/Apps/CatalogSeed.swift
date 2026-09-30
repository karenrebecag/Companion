import Foundation

/// 16k-2d. Incredible's Apps page shows its featured catalog from the first
/// launch; ours went blank behind the setup form until the function was
/// deployed. This seed is the same featured list, so the page is alive
/// before any backend exists — tapping Conectar routes to setup instead.
/// No third-party mark ships in the repo: icons load from each brand's own
/// favicon at display time, like the live catalog's URLs do. That display
/// fetch goes through Google's favicon service — a dozen domain lookups a
/// third party sees whenever the page opens (review 19-1c).
public enum CatalogSeed {
    public static func apps(language: AppLanguage) -> [CatalogApp] {
        let es = language == .es
        return [
            app("slack", "Slack", "slack.com",
                es ? "Manda mensajes y respuestas y mantén tus canales al día."
                   : "Send Slack messages and replies and keep your channels tidy."),
            app("gmail", "Gmail", "gmail.com",
                es ? "Redacta respuestas, encuentra un hilo y limpia tu inbox hablando."
                   : "Draft replies, find a thread, and clear your inbox by talking."),
            app("microsoft_teams", "Microsoft Teams", "teams.microsoft.com",
                es ? "Mensajes a tus canales y chats de Teams sin cambiar de app."
                   : "Message your Teams channels and chats without switching apps."),
            app("microsoft_excel", "Microsoft Excel", "microsoft.com",
                es ? "Agrega filas, busca datos y mantén un libro al día."
                   : "Add rows, look something up, and keep a workbook current."),
            app("google_calendar", "Google Calendar", "calendar.google.com",
                es ? "Agenda reuniones, mira tu día y encuentra un hueco libre."
                   : "Schedule meetings, see your day, and find a free slot."),
            app("google_drive", "Google Drive", "drive.google.com",
                es ? "Encuentra un archivo, compártelo y organiza tu Drive hablando."
                   : "Find a file, share it, and organize your Drive by talking."),
            app("outlook", "Outlook Email", "outlook.com",
                es ? "Redacta respuestas, encuentra un correo y limpia tu inbox."
                   : "Draft replies, find an email, and clear your inbox by talking."),
            app("outlook_calendar", "Outlook Calendar", "outlook.com",
                es ? "Agenda reuniones de Outlook y encuentra un hueco libre."
                   : "Schedule Outlook meetings, see your day, and find a free slot."),
            app("microsoft_onedrive", "Microsoft OneDrive", "onedrive.live.com",
                es ? "Encuentra, comparte y organiza tus archivos de OneDrive."
                   : "Find, share, and organize your OneDrive files by talking."),
            app("sharepoint", "SharePoint", "sharepoint.com",
                es ? "Encuentra archivos y listas en tus sitios de SharePoint."
                   : "Find files and list items across your SharePoint sites."),
            app("notion", "Notion", "notion.so",
                es ? "Crea páginas, busca notas y mantén tu espacio al día."
                   : "Create pages, find notes, and keep your workspace current."),
            app("google_sheets", "Google Sheets", "docs.google.com",
                es ? "Agrega filas, lee datos y mantén una hoja al día."
                   : "Add rows, read data, and keep a sheet current."),
        ]
    }

    /// The page's local search over the seed, same contains the live
    /// catalog's query uses.
    public static func filtered(_ query: String, language: AppLanguage) -> [CatalogApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps(language: language) }
        return apps(language: language).filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private static func app(
        _ slug: String, _ name: String, _ domain: String, _ description: String
    ) -> CatalogApp {
        CatalogApp(
            slug: slug, name: name, description: description,
            icon: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"))
    }
}
