// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct QCControlStrings {
    static let title = "QC Control"

    let description: String
    let pair: String
    let find: String
    let choose: String
    let checking: String
    let connecting: String
    let permission: String
    let bluetoothOff: String
    let connectionFailed: String
    let controlFailed: String
    let noCustomMode: String
    let noiseCancellation: String
    let listeningMode: String
}

extension FeatureStrings {
    static func qcControl(_ language: AppLanguage) -> QCControlStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

private extension QCControlStrings {
    static let enUS = QCControlStrings(
        description: "Switch listening modes, adjust noise cancellation, and check the battery on Bose QuietComfort Ultra headphones.",
        pair: "Pair your Bose QuietComfort Ultra headphones in Bluetooth Settings, then find them here.",
        find: "Find Headphones",
        choose: "Choose headphones",
        checking: "Waiting for Bluetooth…",
        connecting: "Connecting to headphones…",
        permission: "Allow Vorssaint to use Bluetooth in Privacy & Security settings.",
        bluetoothOff: "Turn on Bluetooth to connect to your headphones.",
        connectionFailed: "Could not connect. Make sure the headphones are on and connected to this Mac, then try again.",
        controlFailed: "Could not confirm the headphone settings. Reconnect and check the current mode.",
        noCustomMode: "Free a custom listening mode in the Bose app to adjust this level.",
        noiseCancellation: "Noise cancellation",
        listeningMode: "Listening mode"
    )

    static let ptBR = QCControlStrings(
        description: "Alterne os modos de áudio, ajuste o cancelamento de ruído e veja a bateria dos fones Bose QuietComfort Ultra.",
        pair: "Emparelhe os fones Bose QuietComfort Ultra nos Ajustes de Bluetooth e procure por eles aqui.",
        find: "Buscar fones",
        choose: "Escolher fones",
        checking: "Aguardando o Bluetooth…",
        connecting: "Conectando aos fones…",
        permission: "Permita que o Vorssaint use o Bluetooth nos ajustes de Privacidade e Segurança.",
        bluetoothOff: "Ative o Bluetooth para se conectar aos fones.",
        connectionFailed: "Não foi possível conectar. Verifique se os fones estão ligados e conectados a este Mac e tente novamente.",
        controlFailed: "Não foi possível confirmar os ajustes dos fones. Reconecte e verifique o modo atual.",
        noCustomMode: "Libere um modo de áudio personalizado no app Bose para ajustar este nível.",
        noiseCancellation: "Cancelamento de ruído",
        listeningMode: "Modo de áudio"
    )

    static let tr = QCControlStrings(
        description: "Bose QuietComfort Ultra kulaklığınızda dinleme modunu değiştirin, gürültü engellemeyi ayarlayın ve pil durumunu görün.",
        pair: "Bose QuietComfort Ultra kulaklığınızı Bluetooth ayarlarında eşleyin, ardından burada arayın.",
        find: "Kulaklığı Bul",
        choose: "Kulaklık seçin",
        checking: "Bluetooth bekleniyor…",
        connecting: "Kulaklığa bağlanılıyor…",
        permission: "Gizlilik ve Güvenlik ayarlarında Vorssaint’in Bluetooth kullanmasına izin verin.",
        bluetoothOff: "Kulaklığınıza bağlanmak için Bluetooth’u açın.",
        connectionFailed: "Bağlanılamadı. Kulaklığın açık ve bu Mac’e bağlı olduğunu kontrol edip tekrar deneyin.",
        controlFailed: "Kulaklık ayarları doğrulanamadı. Yeniden bağlanıp geçerli modu kontrol edin.",
        noCustomMode: "Bu düzeyi ayarlamak için Bose uygulamasında bir özel dinleme modu yuvasını boşaltın.",
        noiseCancellation: "Gürültü engelleme",
        listeningMode: "Dinleme modu"
    )

    static let ru = QCControlStrings(
        description: "Меняйте режим прослушивания и уровень шумоподавления, проверяйте заряд наушников Bose QuietComfort Ultra.",
        pair: "Создайте пару с наушниками Bose QuietComfort Ultra в настройках Bluetooth, затем найдите их здесь.",
        find: "Найти наушники",
        choose: "Выберите наушники",
        checking: "Ожидание Bluetooth…",
        connecting: "Подключение к наушникам…",
        permission: "Разрешите Vorssaint использовать Bluetooth в настройках конфиденциальности и безопасности.",
        bluetoothOff: "Включите Bluetooth для подключения наушников.",
        connectionFailed: "Не удалось подключиться. Убедитесь, что наушники включены и подключены к этому Mac, затем повторите попытку.",
        controlFailed: "Не удалось подтвердить настройки наушников. Подключитесь снова и проверьте текущий режим.",
        noCustomMode: "Чтобы изменить уровень, освободите место для пользовательского режима в приложении Bose.",
        noiseCancellation: "Шумоподавление",
        listeningMode: "Режим прослушивания"
    )

    static let es = QCControlStrings(
        description: "Cambia el modo de escucha, ajusta la cancelación de ruido y consulta la batería de los auriculares Bose QuietComfort Ultra.",
        pair: "Enlaza los auriculares Bose QuietComfort Ultra en los ajustes de Bluetooth y búscalos aquí.",
        find: "Buscar auriculares",
        choose: "Elige los auriculares",
        checking: "Esperando a Bluetooth…",
        connecting: "Conectando con los auriculares…",
        permission: "Permite que Vorssaint use Bluetooth en los ajustes de Privacidad y seguridad.",
        bluetoothOff: "Activa Bluetooth para conectarte a los auriculares.",
        connectionFailed: "No se pudo conectar. Comprueba que los auriculares estén encendidos y conectados a este Mac y vuelve a intentarlo.",
        controlFailed: "No se pudieron confirmar los ajustes de los auriculares. Vuelve a conectarlos y comprueba el modo actual.",
        noCustomMode: "Libera un modo de escucha personalizado en la app de Bose para ajustar este nivel.",
        noiseCancellation: "Cancelación de ruido",
        listeningMode: "Modo de escucha"
    )

    static let sk = QCControlStrings(
        description: "Prepínajte režimy počúvania, upravujte potlačenie hluku a sledujte batériu slúchadiel Bose QuietComfort Ultra.",
        pair: "Spárujte slúchadlá Bose QuietComfort Ultra v nastaveniach Bluetooth a potom ich vyhľadajte tu.",
        find: "Vyhľadať slúchadlá",
        choose: "Vyberte slúchadlá",
        checking: "Čaká sa na Bluetooth…",
        connecting: "Pripájajú sa slúchadlá…",
        permission: "Povoľte aplikácii Vorssaint používať Bluetooth v nastaveniach súkromia a bezpečnosti.",
        bluetoothOff: "Zapnite Bluetooth, aby sa slúchadlá mohli pripojiť.",
        connectionFailed: "Pripojenie zlyhalo. Skontrolujte, či sú slúchadlá zapnuté a pripojené k tomuto Macu, a skúste to znova.",
        controlFailed: "Nastavenia slúchadiel sa nepodarilo potvrdiť. Znova ich pripojte a skontrolujte aktuálny režim.",
        noCustomMode: "Ak chcete upraviť túto úroveň, uvoľnite vlastný režim počúvania v aplikácii Bose.",
        noiseCancellation: "Potlačenie hluku",
        listeningMode: "Režim počúvania"
    )

    static let de = QCControlStrings(
        description: "Wechsle den Hörmodus, passe die Geräuschunterdrückung an und prüfe den Akkustand deiner Bose QuietComfort Ultra Kopfhörer.",
        pair: "Kopple deine Bose QuietComfort Ultra Kopfhörer in den Bluetooth-Einstellungen und suche sie anschließend hier.",
        find: "Kopfhörer suchen",
        choose: "Kopfhörer auswählen",
        checking: "Warten auf Bluetooth…",
        connecting: "Kopfhörer werden verbunden…",
        permission: "Erlaube Vorssaint den Bluetooth-Zugriff unter Datenschutz & Sicherheit.",
        bluetoothOff: "Aktiviere Bluetooth, um deine Kopfhörer zu verbinden.",
        connectionFailed: "Verbindung fehlgeschlagen. Prüfe, ob die Kopfhörer eingeschaltet und mit diesem Mac verbunden sind, und versuche es erneut.",
        controlFailed: "Die Kopfhörereinstellungen konnten nicht bestätigt werden. Verbinde die Kopfhörer erneut und prüfe den aktuellen Modus.",
        noCustomMode: "Gib in der Bose-App einen benutzerdefinierten Hörmodus frei, um diese Stufe anzupassen.",
        noiseCancellation: "Geräuschunterdrückung",
        listeningMode: "Hörmodus"
    )

    static let fr = QCControlStrings(
        description: "Changez de mode d’écoute, ajustez la réduction du bruit et consultez la batterie de votre casque Bose QuietComfort Ultra.",
        pair: "Jumelez votre casque Bose QuietComfort Ultra dans les réglages Bluetooth, puis recherchez-le ici.",
        find: "Rechercher le casque",
        choose: "Choisir un casque",
        checking: "En attente du Bluetooth…",
        connecting: "Connexion au casque…",
        permission: "Autorisez Vorssaint à utiliser le Bluetooth dans Confidentialité et sécurité.",
        bluetoothOff: "Activez le Bluetooth pour connecter votre casque.",
        connectionFailed: "Connexion impossible. Vérifiez que le casque est allumé et connecté à ce Mac, puis réessayez.",
        controlFailed: "Impossible de confirmer les réglages du casque. Reconnectez-le et vérifiez le mode actuel.",
        noCustomMode: "Libérez un mode d’écoute personnalisé dans l’app Bose pour ajuster ce niveau.",
        noiseCancellation: "Réduction du bruit",
        listeningMode: "Mode d’écoute"
    )

    static let it = QCControlStrings(
        description: "Cambia modalità di ascolto, regola la cancellazione del rumore e controlla la batteria delle cuffie Bose QuietComfort Ultra.",
        pair: "Abbina le cuffie Bose QuietComfort Ultra nelle impostazioni Bluetooth, poi cercale qui.",
        find: "Cerca cuffie",
        choose: "Scegli le cuffie",
        checking: "In attesa del Bluetooth…",
        connecting: "Connessione alle cuffie…",
        permission: "Consenti a Vorssaint di usare il Bluetooth nelle impostazioni Privacy e sicurezza.",
        bluetoothOff: "Attiva il Bluetooth per collegare le cuffie.",
        connectionFailed: "Connessione non riuscita. Verifica che le cuffie siano accese e collegate a questo Mac e riprova.",
        controlFailed: "Impossibile confermare le impostazioni delle cuffie. Ricollegale e controlla la modalità attuale.",
        noCustomMode: "Libera una modalità di ascolto personalizzata nell’app Bose per regolare questo livello.",
        noiseCancellation: "Cancellazione del rumore",
        listeningMode: "Modalità di ascolto"
    )

    static let ja = QCControlStrings(
        description: "Bose QuietComfort Ultraヘッドホンのリスニングモードやノイズキャンセリングを調整し、バッテリー残量を確認します。",
        pair: "Bluetooth設定でBose QuietComfort Ultraヘッドホンをペアリングしてから、ここで検索してください。",
        find: "ヘッドホンを探す",
        choose: "ヘッドホンを選択",
        checking: "Bluetoothを待機中…",
        connecting: "ヘッドホンに接続中…",
        permission: "「プライバシーとセキュリティ」でVorssaintのBluetoothの使用を許可してください。",
        bluetoothOff: "ヘッドホンに接続するにはBluetoothをオンにしてください。",
        connectionFailed: "接続できませんでした。ヘッドホンがオンで、このMacに接続されていることを確認してから、やり直してください。",
        controlFailed: "ヘッドホンの設定を確認できませんでした。再接続して現在のモードを確認してください。",
        noCustomMode: "レベルを調整するには、Boseアプリでカスタムリスニングモードの空き枠を作ってください。",
        noiseCancellation: "ノイズキャンセリング",
        listeningMode: "リスニングモード"
    )

    static let ko = QCControlStrings(
        description: "Bose QuietComfort Ultra 헤드폰의 청취 모드를 바꾸고, 노이즈 캔슬링을 조절하고, 배터리 잔량을 확인합니다.",
        pair: "Bluetooth 설정에서 Bose QuietComfort Ultra 헤드폰을 페어링한 다음 여기에서 찾으세요.",
        find: "헤드폰 찾기",
        choose: "헤드폰 선택",
        checking: "Bluetooth 대기 중…",
        connecting: "헤드폰 연결 중…",
        permission: "개인정보 보호 및 보안 설정에서 Vorssaint의 Bluetooth 사용을 허용하세요.",
        bluetoothOff: "헤드폰을 연결하려면 Bluetooth를 켜세요.",
        connectionFailed: "연결하지 못했습니다. 헤드폰이 켜져 있고 이 Mac에 연결되어 있는지 확인한 다음 다시 시도하세요.",
        controlFailed: "헤드폰 설정을 확인하지 못했습니다. 다시 연결하고 현재 모드를 확인하세요.",
        noCustomMode: "이 레벨을 조절하려면 Bose 앱에서 사용자 설정 청취 모드 슬롯을 비우세요.",
        noiseCancellation: "노이즈 캔슬링",
        listeningMode: "청취 모드"
    )

    static let uk = QCControlStrings(
        description: "Перемикайте режими прослуховування, регулюйте шумозаглушення й перевіряйте заряд навушників Bose QuietComfort Ultra.",
        pair: "Створіть пару з навушниками Bose QuietComfort Ultra в параметрах Bluetooth, а потім знайдіть їх тут.",
        find: "Знайти навушники",
        choose: "Виберіть навушники",
        checking: "Очікування Bluetooth…",
        connecting: "Під’єднання навушників…",
        permission: "Дозвольте Vorssaint використовувати Bluetooth у параметрах приватності й безпеки.",
        bluetoothOff: "Увімкніть Bluetooth, щоб під’єднати навушники.",
        connectionFailed: "Не вдалося під’єднатися. Переконайтеся, що навушники ввімкнені й під’єднані до цього Mac, і спробуйте ще раз.",
        controlFailed: "Не вдалося підтвердити параметри навушників. Під’єднайте їх знову й перевірте поточний режим.",
        noCustomMode: "Звільніть місце для власного режиму прослуховування в застосунку Bose, щоб налаштувати цей рівень.",
        noiseCancellation: "Шумозаглушення",
        listeningMode: "Режим прослуховування"
    )

    static let zhHans = QCControlStrings(
        description: "切换 Bose QuietComfort Ultra 头戴式耳机的聆听模式、调节降噪并查看电量。",
        pair: "在蓝牙设置中配对 Bose QuietComfort Ultra 头戴式耳机，然后在这里查找。",
        find: "查找耳机",
        choose: "选择耳机",
        checking: "正在等待蓝牙…",
        connecting: "正在连接耳机…",
        permission: "请在「隐私与安全性」中允许 Vorssaint 使用蓝牙。",
        bluetoothOff: "打开蓝牙以连接耳机。",
        connectionFailed: "无法连接。请确认耳机已打开并连接到这台 Mac，然后重试。",
        controlFailed: "无法确认耳机设置。请重新连接并检查当前模式。",
        noCustomMode: "请在 Bose App 中腾出一个自定义聆听模式，以便调节此级别。",
        noiseCancellation: "降噪",
        listeningMode: "聆听模式"
    )

    static let zhTW = QCControlStrings(
        description: "切換 Bose QuietComfort Ultra 頭戴式耳機的聆聽模式、調整降噪並查看電量。",
        pair: "在藍牙設定中配對 Bose QuietComfort Ultra 頭戴式耳機，再到這裡尋找。",
        find: "尋找耳機",
        choose: "選擇耳機",
        checking: "正在等待藍牙…",
        connecting: "正在連接耳機…",
        permission: "請在「隱私權與安全性」設定中允許 Vorssaint 使用藍牙。",
        bluetoothOff: "開啟藍牙以連接耳機。",
        connectionFailed: "無法連接。請確認耳機已開啟並連接至這部 Mac，然後再試一次。",
        controlFailed: "無法確認耳機設定。請重新連接並檢查目前的模式。",
        noCustomMode: "請在 Bose App 中騰出一個自訂聆聽模式，才能調整此等級。",
        noiseCancellation: "降噪",
        listeningMode: "聆聽模式"
    )

    static let zhHK = QCControlStrings(
        description: "切換 Bose QuietComfort Ultra 頭戴式耳機的聆聽模式、調校降噪並查看電量。",
        pair: "在藍牙設定配對 Bose QuietComfort Ultra 頭戴式耳機，再在這裏尋找。",
        find: "尋找耳機",
        choose: "選擇耳機",
        checking: "正在等待藍牙…",
        connecting: "正在連接耳機…",
        permission: "請在「私隱與保安」設定允許 Vorssaint 使用藍牙。",
        bluetoothOff: "開啟藍牙以連接耳機。",
        connectionFailed: "未能連接。請確認耳機已開啟及連接到這部 Mac，然後再試。",
        controlFailed: "未能確認耳機設定。請重新連接並檢查目前的模式。",
        noCustomMode: "請在 Bose App 騰出一個自訂聆聽模式，以調校此等級。",
        noiseCancellation: "降噪",
        listeningMode: "聆聽模式"
    )
}
