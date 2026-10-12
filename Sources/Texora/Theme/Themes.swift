import Foundation

/// All built-in themes. Palettes follow each scheme's published colours.
enum Themes {
    static let light: [Theme] = [
        defaultLight, paper, catppuccinLatte, oneLight, gruvboxLight, solarizedLight, rosePineDawn, githubLight,
    ]
    static let dark: [Theme] = [
        defaultDark, catppuccinMocha, catppuccinMacchiato, oneDark, gruvboxDark, dracula, nord, tokyoNight,
        solarizedDark, rosePine, rosePineMoon, githubDark,
    ]
    static let all: [Theme] = light + dark

    static func byID(_ id: String) -> Theme? { all.first { $0.id == id } }

    // MARK: Light

    static let defaultLight = Theme(
        id: "default-light", name: "Texora Light", isDark: false,
        bg: "#FFFFFF", sidebar: "#F5F5F7", surface: "#F0F0F3", elevated: "#FFFFFF", border: "#E3E3E8",
        text: "#1D1D22", textSecondary: "#5C5C66", textMuted: "#9A9AA3", accent: "#7C3AED", selection: "#E7E2F8",
        success: "#1F9D55", warning: "#B7791F", danger: "#D92D20",
        synCommand: "#7C3AED", synKeyword: "#2563EB", synEnv: "#B45309", synMath: "#047857",
        synComment: "#9A9AA3", synBracket: "#5C5C66", synNumber: "#C2410C", synString: "#047857")

    static let paper = Theme(
        id: "paper", name: "Paper", isDark: false,
        bg: "#F7F3EA", sidebar: "#EFE9DC", surface: "#EAE3D2", elevated: "#FBF8F1", border: "#DDD3BF",
        text: "#3A352C", textSecondary: "#6B6354", textMuted: "#9C9381", accent: "#A8532F", selection: "#E8DCC4",
        success: "#5B7F2B", warning: "#A66A00", danger: "#B03A2E",
        synCommand: "#A8532F", synKeyword: "#2F5F8A", synEnv: "#8A6A12", synMath: "#4F7A3A",
        synComment: "#A39A87", synBracket: "#6B6354", synNumber: "#9C4A1A", synString: "#4F7A3A")

    static let catppuccinLatte = Theme(
        id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false,
        bg: "#EFF1F5", sidebar: "#E6E9EF", surface: "#DCE0E8", elevated: "#EFF1F5", border: "#CCD0DA",
        text: "#4C4F69", textSecondary: "#6C6F85", textMuted: "#9CA0B0", accent: "#8839EF", selection: "#CCD0DA",
        success: "#40A02B", warning: "#DF8E1D", danger: "#D20F39",
        synCommand: "#8839EF", synKeyword: "#1E66F5", synEnv: "#DF8E1D", synMath: "#40A02B",
        synComment: "#9CA0B0", synBracket: "#7C7F93", synNumber: "#FE640B", synString: "#40A02B")

    static let oneLight = Theme(
        id: "one-light", name: "One Light", isDark: false,
        bg: "#FAFAFA", sidebar: "#F0F0F1", surface: "#EAEAEB", elevated: "#FFFFFF", border: "#DBDBDC",
        text: "#383A42", textSecondary: "#696C77", textMuted: "#A0A1A7", accent: "#4078F2", selection: "#E5E5E6",
        success: "#50A14F", warning: "#C18401", danger: "#E45649",
        synCommand: "#A626A4", synKeyword: "#4078F2", synEnv: "#C18401", synMath: "#50A14F",
        synComment: "#A0A1A7", synBracket: "#696C77", synNumber: "#986801", synString: "#50A14F")

    static let gruvboxLight = Theme(
        id: "gruvbox-light", name: "Gruvbox Light", isDark: false,
        bg: "#FBF1C7", sidebar: "#F2E5BC", surface: "#EBDBB2", elevated: "#F9F5D7", border: "#D5C4A1",
        text: "#3C3836", textSecondary: "#665C54", textMuted: "#928374", accent: "#AF3A03", selection: "#EBDBB2",
        success: "#79740E", warning: "#B57614", danger: "#9D0006",
        synCommand: "#9D0006", synKeyword: "#076678", synEnv: "#B57614", synMath: "#79740E",
        synComment: "#928374", synBracket: "#665C54", synNumber: "#8F3F71", synString: "#427B58")

    static let solarizedLight = Theme(
        id: "solarized-light", name: "Solarized Light", isDark: false,
        bg: "#FDF6E3", sidebar: "#EEE8D5", surface: "#E9E2CB", elevated: "#FDF6E3", border: "#DDD6C1",
        text: "#52676E", textSecondary: "#657B83", textMuted: "#93A1A1", accent: "#268BD2", selection: "#EEE8D5",
        success: "#859900", warning: "#B58900", danger: "#DC322F",
        synCommand: "#268BD2", synKeyword: "#859900", synEnv: "#B58900", synMath: "#2AA198",
        synComment: "#93A1A1", synBracket: "#657B83", synNumber: "#D33682", synString: "#2AA198")

    static let rosePineDawn = Theme(
        id: "rose-pine-dawn", name: "Rosé Pine Dawn", isDark: false,
        bg: "#FAF4ED", sidebar: "#F2E9E1", surface: "#F4EDE8", elevated: "#FFFAF3", border: "#DFDAD9",
        text: "#575279", textSecondary: "#797593", textMuted: "#9893A5", accent: "#907AA9", selection: "#DFDAD9",
        success: "#286983", warning: "#EA9D34", danger: "#B4637A",
        synCommand: "#907AA9", synKeyword: "#286983", synEnv: "#EA9D34", synMath: "#56949F",
        synComment: "#9893A5", synBracket: "#797593", synNumber: "#D7827E", synString: "#56949F")

    static let githubLight = Theme(
        id: "github-light", name: "GitHub Light", isDark: false,
        bg: "#FFFFFF", sidebar: "#F6F8FA", surface: "#EFF2F5", elevated: "#FFFFFF", border: "#D0D7DE",
        text: "#1F2328", textSecondary: "#57606A", textMuted: "#8C959F", accent: "#0969DA", selection: "#DDF4FF",
        success: "#1A7F37", warning: "#9A6700", danger: "#CF222E",
        synCommand: "#CF222E", synKeyword: "#8250DF", synEnv: "#953800", synMath: "#0550AE",
        synComment: "#6E7781", synBracket: "#57606A", synNumber: "#0550AE", synString: "#0A3069")

    // MARK: Dark

    static let defaultDark = Theme(
        id: "default-dark", name: "Texora Dark", isDark: true,
        bg: "#1B1B1F", sidebar: "#151518", surface: "#25252B", elevated: "#2B2B32", border: "#2E2E35",
        text: "#E6E6EA", textSecondary: "#A1A1AA", textMuted: "#71717A", accent: "#A78BFA", selection: "#34343D",
        success: "#4ADE80", warning: "#FBBF24", danger: "#F87171",
        synCommand: "#C4B5FD", synKeyword: "#7DD3FC", synEnv: "#FCD34D", synMath: "#86EFAC",
        synComment: "#6B6B75", synBracket: "#A1A1AA", synNumber: "#FDBA74", synString: "#86EFAC")

    static let catppuccinMocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
        bg: "#1E1E2E", sidebar: "#181825", surface: "#262637", elevated: "#313244", border: "#2A2A3C",
        text: "#CDD6F4", textSecondary: "#A6ADC8", textMuted: "#7F849C", accent: "#CBA6F7", selection: "#313244",
        success: "#A6E3A1", warning: "#F9E2AF", danger: "#F38BA8",
        synCommand: "#CBA6F7", synKeyword: "#89B4FA", synEnv: "#F9E2AF", synMath: "#A6E3A1",
        synComment: "#6C7086", synBracket: "#9399B2", synNumber: "#FAB387", synString: "#A6E3A1")

    static let catppuccinMacchiato = Theme(
        id: "catppuccin-macchiato", name: "Catppuccin Macchiato", isDark: true,
        bg: "#24273A", sidebar: "#1E2030", surface: "#2C3045", elevated: "#363A4F", border: "#30344A",
        text: "#CAD3F5", textSecondary: "#A5ADCB", textMuted: "#8087A2", accent: "#C6A0F6", selection: "#363A4F",
        success: "#A6DA95", warning: "#EED49F", danger: "#ED8796",
        synCommand: "#C6A0F6", synKeyword: "#8AADF4", synEnv: "#EED49F", synMath: "#A6DA95",
        synComment: "#6E738D", synBracket: "#939AB7", synNumber: "#F5A97F", synString: "#A6DA95")

    static let oneDark = Theme(
        id: "one-dark", name: "One Dark", isDark: true,
        bg: "#282C34", sidebar: "#21252B", surface: "#2F343E", elevated: "#353B45", border: "#181A1F",
        text: "#ABB2BF", textSecondary: "#8B929E", textMuted: "#5C6370", accent: "#61AFEF", selection: "#3E4451",
        success: "#98C379", warning: "#E5C07B", danger: "#E06C75",
        synCommand: "#C678DD", synKeyword: "#61AFEF", synEnv: "#E5C07B", synMath: "#98C379",
        synComment: "#5C6370", synBracket: "#8B929E", synNumber: "#D19A66", synString: "#98C379")

    static let gruvboxDark = Theme(
        id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true,
        bg: "#282828", sidebar: "#1D2021", surface: "#32302F", elevated: "#3C3836", border: "#3C3836",
        text: "#EBDBB2", textSecondary: "#BDAE93", textMuted: "#928374", accent: "#FABD2F", selection: "#504945",
        success: "#B8BB26", warning: "#FABD2F", danger: "#FB4934",
        synCommand: "#FB4934", synKeyword: "#83A598", synEnv: "#FABD2F", synMath: "#B8BB26",
        synComment: "#928374", synBracket: "#BDAE93", synNumber: "#D3869B", synString: "#8EC07C")

    static let dracula = Theme(
        id: "dracula", name: "Dracula", isDark: true,
        bg: "#282A36", sidebar: "#21222C", surface: "#303241", elevated: "#343746", border: "#191A21",
        text: "#F8F8F2", textSecondary: "#BFBFD0", textMuted: "#6272A4", accent: "#BD93F9", selection: "#44475A",
        success: "#50FA7B", warning: "#F1FA8C", danger: "#FF5555",
        synCommand: "#FF79C6", synKeyword: "#8BE9FD", synEnv: "#F1FA8C", synMath: "#50FA7B",
        synComment: "#6272A4", synBracket: "#BFBFD0", synNumber: "#BD93F9", synString: "#50FA7B")

    static let nord = Theme(
        id: "nord", name: "Nord", isDark: true,
        bg: "#2E3440", sidebar: "#272C36", surface: "#353C4A", elevated: "#3B4252", border: "#3B4252",
        text: "#D8DEE9", textSecondary: "#A9B1C1", textMuted: "#616E88", accent: "#88C0D0", selection: "#434C5E",
        success: "#A3BE8C", warning: "#EBCB8B", danger: "#BF616A",
        synCommand: "#81A1C1", synKeyword: "#88C0D0", synEnv: "#EBCB8B", synMath: "#A3BE8C",
        synComment: "#616E88", synBracket: "#A9B1C1", synNumber: "#B48EAD", synString: "#A3BE8C")

    static let tokyoNight = Theme(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        bg: "#1A1B26", sidebar: "#16161E", surface: "#20222F", elevated: "#292E42", border: "#1F2335",
        text: "#C0CAF5", textSecondary: "#A9B1D6", textMuted: "#565F89", accent: "#7AA2F7", selection: "#292E42",
        success: "#9ECE6A", warning: "#E0AF68", danger: "#F7768E",
        synCommand: "#BB9AF7", synKeyword: "#7AA2F7", synEnv: "#E0AF68", synMath: "#9ECE6A",
        synComment: "#565F89", synBracket: "#A9B1D6", synNumber: "#FF9E64", synString: "#73DACA")

    static let solarizedDark = Theme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        bg: "#002B36", sidebar: "#00252F", surface: "#073642", elevated: "#0A3D4A", border: "#0A3D4A",
        text: "#93A1A1", textSecondary: "#839496", textMuted: "#586E75", accent: "#268BD2", selection: "#073642",
        success: "#859900", warning: "#B58900", danger: "#DC322F",
        synCommand: "#268BD2", synKeyword: "#859900", synEnv: "#B58900", synMath: "#2AA198",
        synComment: "#586E75", synBracket: "#839496", synNumber: "#D33682", synString: "#2AA198")

    static let rosePine = Theme(
        id: "rose-pine", name: "Rosé Pine", isDark: true,
        bg: "#191724", sidebar: "#16141F", surface: "#1F1D2E", elevated: "#26233A", border: "#26233A",
        text: "#E0DEF4", textSecondary: "#908CAA", textMuted: "#6E6A86", accent: "#C4A7E7", selection: "#403D52",
        success: "#9CCFD8", warning: "#F6C177", danger: "#EB6F92",
        synCommand: "#C4A7E7", synKeyword: "#31748F", synEnv: "#F6C177", synMath: "#9CCFD8",
        synComment: "#6E6A86", synBracket: "#908CAA", synNumber: "#EBBCBA", synString: "#9CCFD8")

    static let rosePineMoon = Theme(
        id: "rose-pine-moon", name: "Rosé Pine Moon", isDark: true,
        bg: "#232136", sidebar: "#1E1C30", surface: "#2A273F", elevated: "#393552", border: "#2F2B45",
        text: "#E0DEF4", textSecondary: "#908CAA", textMuted: "#6E6A86", accent: "#C4A7E7", selection: "#44415A",
        success: "#9CCFD8", warning: "#F6C177", danger: "#EB6F92",
        synCommand: "#C4A7E7", synKeyword: "#3E8FB0", synEnv: "#F6C177", synMath: "#9CCFD8",
        synComment: "#6E6A86", synBracket: "#908CAA", synNumber: "#EA9A97", synString: "#9CCFD8")

    static let githubDark = Theme(
        id: "github-dark", name: "GitHub Dark", isDark: true,
        bg: "#0D1117", sidebar: "#010409", surface: "#161B22", elevated: "#1C2128", border: "#21262D",
        text: "#E6EDF3", textSecondary: "#9198A1", textMuted: "#6E7681", accent: "#4493F8", selection: "#1F2937",
        success: "#3FB950", warning: "#D29922", danger: "#F85149",
        synCommand: "#FF7B72", synKeyword: "#D2A8FF", synEnv: "#FFA657", synMath: "#79C0FF",
        synComment: "#8B949E", synBracket: "#9198A1", synNumber: "#79C0FF", synString: "#A5D6FF")
}
