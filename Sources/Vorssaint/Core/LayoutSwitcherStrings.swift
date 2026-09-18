// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LayoutSwitcherStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let shortcutLabel: String
    let shortcutCaption: String
    let automatic: String
    let automaticCaption: String
    let minimumLength: String
    let minimumLengthCaption: String
    let activeNow: String
    let forgetLearned: String
    let forgetLearnedCaption: String
    let learnedForgotten: String
}

extension FeatureStrings {
    static func layoutSwitcher(_ language: AppLanguage) -> LayoutSwitcherStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension LayoutSwitcherStrings {
    static let enUS = LayoutSwitcherStrings(
        pageTitle: "Layout Switcher",
        hubDescription: "Retypes a word that went in on the wrong keyboard layout.",
        enable: "Fix the wrong keyboard layout",
        enableCaption: "Pairs the layouts you have enabled by what each key types, so any two of them work.",
        shortcutLabel: "Shortcut",
        shortcutCaption: "Retypes the selection, or the word before the caret. Press it again to put the word back.",
        automatic: "Correct as you type",
        automaticCaption: "Retypes a finished word on its own. Leave it off to correct only when you ask.",
        minimumLength: "Shortest word to correct",
        minimumLengthCaption: "Automatic correction skips anything shorter.",
        activeNow: "Watching for typing",
        forgetLearned: "Forget learned words",
        forgetLearnedCaption: "Correcting as you type remembers ordinary words you type often and corrections you took back. They stay on this Mac and are left out of exported settings. Nothing with a digit or a symbol in it is kept.",
        learnedForgotten: "Forgotten"
    )

    static let ptBR = LayoutSwitcherStrings(
        pageTitle: "Corretor de layout",
        hubDescription: "Redigita uma palavra escrita com o layout de teclado errado.",
        enable: "Corrigir o layout errado",
        enableCaption: "Combina os layouts ativados pelo que cada tecla digita, então qualquer par funciona.",
        shortcutLabel: "Atalho",
        shortcutCaption: "Redigita a seleção ou a palavra antes do cursor. Pressione de novo para voltar.",
        automatic: "Corrigir enquanto digita",
        automaticCaption: "Redigita sozinho uma palavra terminada. Deixe desligado para corrigir só quando você pedir.",
        minimumLength: "Menor palavra a corrigir",
        minimumLengthCaption: "A correção automática ignora as mais curtas.",
        activeNow: "Acompanhando a digitação",
        forgetLearned: "Esquecer palavras aprendidas",
        forgetLearnedCaption: "A correção ao digitar lembra as palavras comuns que você digita com frequência e as correções que você desfez. Elas ficam neste Mac e não entram nos ajustes exportados. Nada com dígito ou símbolo é guardado.",
        learnedForgotten: "Esquecido"
    )

    static let tr = LayoutSwitcherStrings(
        pageTitle: "Düzen düzeltici",
        hubDescription: "Yanlış klavye düzeninde yazılan bir kelimeyi yeniden yazar.",
        enable: "Yanlış klavye düzenini düzelt",
        enableCaption: "Etkin düzenleri her tuşun yazdığı şeye göre eşler, böylece herhangi bir çift çalışır.",
        shortcutLabel: "Kısayol",
        shortcutCaption: "Seçimi ya da imleçten önceki kelimeyi yeniden yazar. Geri almak için tekrar basın.",
        automatic: "Yazarken düzelt",
        automaticCaption: "Biten bir kelimeyi kendiliğinden yeniden yazar. Yalnızca istediğinizde düzeltmesi için kapalı bırakın.",
        minimumLength: "Düzeltilecek en kısa kelime",
        minimumLengthCaption: "Otomatik düzeltme daha kısalarını atlar.",
        activeNow: "Yazımı izliyor",
        forgetLearned: "Öğrenilen kelimeleri unut",
        forgetLearnedCaption: "Yazarken düzeltme, sık yazdığınız sıradan kelimeleri ve geri aldığınız düzeltmeleri hatırlar. Bunlar bu Mac’te kalır ve dışa aktarılan ayarlara girmez. İçinde rakam veya sembol olan hiçbir şey saklanmaz.",
        learnedForgotten: "Unutuldu"
    )

    static let ru = LayoutSwitcherStrings(
        pageTitle: "Переключатель раскладки",
        hubDescription: "Перенабирает слово, введённое в неправильной раскладке.",
        enable: "Исправлять неправильную раскладку",
        enableCaption: "Сопоставляет включённые раскладки по тому, что печатает каждая клавиша, поэтому работает любая пара.",
        shortcutLabel: "Сочетание клавиш",
        shortcutCaption: "Перенабирает выделенный текст или слово перед курсором. Нажмите ещё раз, чтобы вернуть как было.",
        automatic: "Исправлять во время набора",
        automaticCaption: "Перенабирает законченное слово само. Оставьте выключенным, чтобы исправлять только по запросу.",
        minimumLength: "Минимальная длина слова",
        minimumLengthCaption: "Автоматическое исправление пропускает более короткие.",
        activeNow: "Следит за набором",
        forgetLearned: "Забыть выученные слова",
        forgetLearnedCaption: "Исправление при наборе запоминает обычные слова, которые вы часто набираете, и исправления, которые вы отменили. Они остаются на этом Mac и не попадают в экспортированные настройки. Ничего с цифрой или символом не сохраняется.",
        learnedForgotten: "Забыто"
    )

    static let es = LayoutSwitcherStrings(
        pageTitle: "Corrector de distribución",
        hubDescription: "Vuelve a escribir una palabra tecleada con la distribución de teclado equivocada.",
        enable: "Corregir la distribución equivocada",
        enableCaption: "Empareja las distribuciones activadas según lo que escribe cada tecla, así funciona cualquier par.",
        shortcutLabel: "Atajo",
        shortcutCaption: "Vuelve a escribir la selección o la palabra anterior al cursor. Púlsalo otra vez para deshacerlo.",
        automatic: "Corregir al escribir",
        automaticCaption: "Vuelve a escribir sola una palabra terminada. Déjalo desactivado para corregir solo cuando lo pidas.",
        minimumLength: "Palabra más corta que corregir",
        minimumLengthCaption: "La corrección automática omite las más cortas.",
        activeNow: "Atento a lo que escribes",
        forgetLearned: "Olvidar las palabras aprendidas",
        forgetLearnedCaption: "La corrección al escribir recuerda las palabras corrientes que escribes a menudo y las correcciones que deshiciste. Se quedan en este Mac y no entran en los ajustes exportados. No se guarda nada que lleve un dígito o un símbolo.",
        learnedForgotten: "Olvidado"
    )

    static let de = LayoutSwitcherStrings(
        pageTitle: "Belegungskorrektur",
        hubDescription: "Tippt ein Wort neu, das in der falschen Tastaturbelegung eingegeben wurde.",
        enable: "Falsche Tastaturbelegung korrigieren",
        enableCaption: "Verbindet die aktivierten Belegungen danach, was jede Taste schreibt, sodass jedes Paar funktioniert.",
        shortcutLabel: "Kurzbefehl",
        shortcutCaption: "Tippt die Auswahl neu oder das Wort vor der Einfügemarke. Noch einmal drücken stellt es zurück.",
        automatic: "Beim Tippen korrigieren",
        automaticCaption: "Tippt ein fertiges Wort von selbst neu. Ausgeschaltet wird nur auf Anfrage korrigiert.",
        minimumLength: "Kürzestes Wort zum Korrigieren",
        minimumLengthCaption: "Die automatische Korrektur überspringt kürzere Wörter.",
        activeNow: "Achtet auf Eingaben",
        forgetLearned: "Gelernte Wörter vergessen",
        forgetLearnedCaption: "Die Korrektur beim Tippen merkt sich gewöhnliche Wörter, die du oft tippst, und Korrekturen, die du zurückgenommen hast. Sie bleiben auf diesem Mac und fehlen in exportierten Einstellungen. Nichts mit einer Ziffer oder einem Symbol wird behalten.",
        learnedForgotten: "Vergessen"
    )

    static let fr = LayoutSwitcherStrings(
        pageTitle: "Correcteur de disposition",
        hubDescription: "Retape un mot saisi avec la mauvaise disposition de clavier.",
        enable: "Corriger la mauvaise disposition",
        enableCaption: "Associe les dispositions activées selon ce que tape chaque touche, donc toute paire fonctionne.",
        shortcutLabel: "Raccourci",
        shortcutCaption: "Retape la sélection, ou le mot avant le curseur. Appuyez de nouveau pour revenir en arrière.",
        automatic: "Corriger pendant la saisie",
        automaticCaption: "Retape un mot terminé tout seul. Laissez désactivé pour ne corriger qu’à la demande.",
        minimumLength: "Mot le plus court à corriger",
        minimumLengthCaption: "La correction automatique ignore les mots plus courts.",
        activeNow: "Surveille la saisie",
        forgetLearned: "Oublier les mots appris",
        forgetLearnedCaption: "La correction pendant la saisie retient les mots courants que vous tapez souvent et les corrections que vous avez annulées. Ils restent sur ce Mac et ne figurent pas dans les réglages exportés. Rien qui contienne un chiffre ou un symbole n’est conservé.",
        learnedForgotten: "Oublié"
    )

    static let it = LayoutSwitcherStrings(
        pageTitle: "Correttore di layout",
        hubDescription: "Riscrive una parola digitata con il layout di tastiera sbagliato.",
        enable: "Correggere il layout sbagliato",
        enableCaption: "Abbina i layout attivati in base a ciò che scrive ogni tasto, così funziona qualsiasi coppia.",
        shortcutLabel: "Scorciatoia",
        shortcutCaption: "Riscrive la selezione o la parola prima del cursore. Premila di nuovo per tornare indietro.",
        automatic: "Correggere durante la digitazione",
        automaticCaption: "Riscrive da sola una parola finita. Lasciala disattivata per correggere solo su richiesta.",
        minimumLength: "Parola più corta da correggere",
        minimumLengthCaption: "La correzione automatica salta quelle più corte.",
        activeNow: "In ascolto della digitazione",
        forgetLearned: "Dimentica le parole imparate",
        forgetLearnedCaption: "La correzione durante la digitazione ricorda le parole comuni che digiti spesso e le correzioni che hai annullato. Restano su questo Mac e non entrano nelle impostazioni esportate. Niente che contenga una cifra o un simbolo viene conservato.",
        learnedForgotten: "Dimenticato"
    )

    static let ja = LayoutSwitcherStrings(
        pageTitle: "レイアウト修正",
        hubDescription: "入力ソースを間違えて打った単語を打ち直します。",
        enable: "間違ったキーボードレイアウトを直す",
        enableCaption: "有効にしているレイアウトを、各キーが打つ文字で対応付けます。どの組み合わせでも動きます。",
        shortcutLabel: "ショートカット",
        shortcutCaption: "選択範囲、またはカーソル手前の単語を打ち直します。もう一度押すと元に戻ります。",
        automatic: "入力しながら直す",
        automaticCaption: "打ち終わった単語をひとりでに打ち直します。必要なときだけ直すならオフのままに。",
        minimumLength: "直す最短の単語",
        minimumLengthCaption: "自動修正はこれより短い単語を飛ばします。",
        activeNow: "入力を見ています",
        forgetLearned: "学習した単語を忘れる",
        forgetLearnedCaption: "入力中の修正は、よく入力する通常の単語と、取り消した修正を覚えます。これらはこのMacにだけ残り、書き出した設定には含まれません。数字や記号を含むものは保存されません。",
        learnedForgotten: "忘れました"
    )

    static let ko = LayoutSwitcherStrings(
        pageTitle: "레이아웃 교정기",
        hubDescription: "잘못된 키보드 레이아웃으로 입력한 단어를 다시 입력합니다.",
        enable: "잘못된 키보드 레이아웃 고치기",
        enableCaption: "켜 둔 레이아웃을 각 키가 입력하는 글자로 짝지어, 어떤 조합이든 동작합니다.",
        shortcutLabel: "단축키",
        shortcutCaption: "선택한 글자나 커서 앞 단어를 다시 입력합니다. 다시 누르면 되돌립니다.",
        automatic: "입력하는 동안 고치기",
        automaticCaption: "끝난 단어를 스스로 다시 입력합니다. 요청할 때만 고치려면 꺼 두세요.",
        minimumLength: "고칠 가장 짧은 단어",
        minimumLengthCaption: "자동 교정은 이보다 짧은 단어를 건너뜁니다.",
        activeNow: "입력을 지켜보는 중",
        forgetLearned: "학습한 단어 지우기",
        forgetLearnedCaption: "입력 중 교정은 자주 입력하는 일반 단어와 되돌린 교정을 기억합니다. 이 Mac에만 남으며 내보낸 설정에는 포함되지 않습니다. 숫자나 기호가 들어간 것은 저장하지 않습니다.",
        learnedForgotten: "지웠습니다"
    )

    static let zhHans = LayoutSwitcherStrings(
        pageTitle: "布局纠正",
        hubDescription: "重新输入用错键盘布局打出的单词。",
        enable: "纠正用错的键盘布局",
        enableCaption: "按每个键实际输入的字符配对已启用的布局，任意两种都能用。",
        shortcutLabel: "快捷键",
        shortcutCaption: "重新输入选中的文字，或光标前的单词。再按一次即可还原。",
        automatic: "输入时自动纠正",
        automaticCaption: "自动重新输入打完的单词。保持关闭则只在你要求时纠正。",
        minimumLength: "纠正的最短单词",
        minimumLengthCaption: "自动纠正会跳过更短的单词。",
        activeNow: "正在留意输入",
        forgetLearned: "忘记已学习的词",
        forgetLearnedCaption: "输入时更正会记住你常输入的普通词语和你撤回的更正。它们只留在这台 Mac 上，不会进入导出的设置。带数字或符号的内容不会保存。",
        learnedForgotten: "已忘记"
    )

    static let zhTW = LayoutSwitcherStrings(
        pageTitle: "配置修正",
        hubDescription: "重新輸入用錯鍵盤配置打出的字詞。",
        enable: "修正用錯的鍵盤配置",
        enableCaption: "依每個按鍵實際輸入的字元配對已啟用的配置，任兩種都能用。",
        shortcutLabel: "快速鍵",
        shortcutCaption: "重新輸入選取的文字，或游標前的字詞。再按一次就會還原。",
        automatic: "輸入時自動修正",
        automaticCaption: "自動重新輸入打完的字詞。保持關閉則只在你要求時修正。",
        minimumLength: "要修正的最短字詞",
        minimumLengthCaption: "自動修正會略過更短的字詞。",
        activeNow: "正在留意輸入",
        forgetLearned: "忘記已學習的詞",
        forgetLearnedCaption: "輸入時更正會記住你常輸入的一般詞語和你取消的更正。它們只留在這部 Mac 上，不會進入輸出的設定。含有數字或符號的內容不會儲存。",
        learnedForgotten: "已忘記"
    )

    static let zhHK = LayoutSwitcherStrings(
        pageTitle: "配置修正",
        hubDescription: "重新輸入用錯鍵盤配置打出的字詞。",
        enable: "修正用錯的鍵盤配置",
        enableCaption: "按每個按鍵實際輸入的字元配對已啟用的配置，任何兩種都用得到。",
        shortcutLabel: "快捷鍵",
        shortcutCaption: "重新輸入選取的文字，或游標前的字詞。再按一次就會還原。",
        automatic: "輸入時自動修正",
        automaticCaption: "自動重新輸入打完的字詞。保持關閉就只在你要求時修正。",
        minimumLength: "要修正的最短字詞",
        minimumLengthCaption: "自動修正會略過更短的字詞。",
        activeNow: "正在留意輸入",
        forgetLearned: "忘記已學習的字詞",
        forgetLearnedCaption: "輸入時更正會記住你常輸入的一般字詞和你取消的更正。它們只留在這部 Mac 上，不會進入匯出的設定。含有數字或符號的內容不會儲存。",
        learnedForgotten: "已忘記"
    )
}
