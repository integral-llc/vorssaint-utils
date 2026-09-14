// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct YouTubeTranscriberStrings {
    let pageTitle: String
    let hubDescription: String
    let sourceLabel: String
    let sourcePlaceholder: String
    let start: String
    let cancel: String
    let openTranscript: String
    let showInFinder: String
    let copyTranscript: String
    let phaseReadingTitle: String
    let phaseDownloading: String
    let phaseMeasuring: String
    let phaseUploading: String
    let phaseTranscribing: String
    let phaseFinished: String
    let locationLabel: String
    let locationLocal: String
    let locationRemote: String
    let remoteHostLabel: String
    let remoteHostPlaceholder: String
    let remoteHostCaption: String
    let keepAudio: String
    let keepAudioCaption: String
    let outputFolder: String
    let outputFolderCaption: String
    let helpersSection: String
    let helpersMissingFormat: String
    let helpersReady: String
    let updateButton: String
    let updateChecking: String
    let updateUpToDateFormat: String
    let updateInstalledFormat: String
    let updateFailed: String
    let updateCaption: String
    let failureHelperMissingFormat: String
    let failureHelperStale: String
    let failureVideoUnavailable: String
    let failureVideoPrivate: String
    let failureMembersOnly: String
    let failureAgeRestricted: String
    let failureGeoBlocked: String
    let failureLiveNotFinished: String
    let failureNetwork: String
    let failureNotMedia: String
    let failureDiskFull: String
    let failureRemoteUnreachable: String
    let failureRemoteRejectedFormat: String
    let failureCancelled: String
    let failureHelperFailedFormat: String
    let failureUnknown: String

    func message(for failure: TranscriptionFailure) -> String {
        switch failure {
        case .helperMissing(let helper):
            return String(format: failureHelperMissingFormat, helper.rawValue)
        case .helperStale: return failureHelperStale
        case .videoUnavailable: return failureVideoUnavailable
        case .videoPrivate: return failureVideoPrivate
        case .videoMembersOnly: return failureMembersOnly
        case .videoAgeRestricted: return failureAgeRestricted
        case .videoGeoBlocked: return failureGeoBlocked
        case .liveNotFinished: return failureLiveNotFinished
        case .networkUnreachable: return failureNetwork
        case .notMedia: return failureNotMedia
        case .diskFull: return failureDiskFull
        case .remoteUnreachable: return failureRemoteUnreachable
        case .remoteRejected(let status):
            return String(format: failureRemoteRejectedFormat, status)
        case .cancelled: return failureCancelled
        case .helperFailed(let helper, let code):
            return String(format: failureHelperFailedFormat, helper.rawValue, code)
        case .unknown: return failureUnknown
        }
    }

    func label(for phase: TranscriptionPhase) -> String? {
        switch phase {
        case .idle, .failed: return nil
        case .readingTitle: return phaseReadingTitle
        case .downloadingAudio: return phaseDownloading
        case .measuringAudio: return phaseMeasuring
        case .uploading: return phaseUploading
        case .transcribing: return phaseTranscribing
        case .finished: return phaseFinished
        }
    }
}

extension FeatureStrings {
    static func youtubeTranscriber(_ language: AppLanguage) -> YouTubeTranscriberStrings {
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

extension YouTubeTranscriberStrings {
    static let enUS = YouTubeTranscriberStrings(
        pageTitle: "Transcriber",
        hubDescription: "Turns a video link or a file you drop in into a text transcript.",
        sourceLabel: "Video link or file",
        sourcePlaceholder: "Paste a link, or drop an audio or video file",
        start: "Transcribe",
        cancel: "Stop",
        openTranscript: "Open transcript",
        showInFinder: "Show in Finder",
        copyTranscript: "Copy transcript",
        phaseReadingTitle: "Reading the title",
        phaseDownloading: "Fetching the audio",
        phaseMeasuring: "Measuring the audio",
        phaseUploading: "Uploading",
        phaseTranscribing: "Transcribing",
        phaseFinished: "Done",
        locationLabel: "Transcribe",
        locationLocal: "On this Mac",
        locationRemote: "On a server you run",
        remoteHostLabel: "Server",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "A whisper.cpp server of your own. Without a scheme it is reached over https, so the audio does not travel in the clear.",
        keepAudio: "Keep the audio file",
        keepAudioCaption: "The extracted audio is deleted once the transcript is written.",
        outputFolder: "Save to",
        outputFolderCaption: "Transcripts land in Downloads unless you pick somewhere else.",
        helpersSection: "Helpers",
        helpersMissingFormat: "Missing: %@. Transcription needs them.",
        helpersReady: "All helpers are installed.",
        updateButton: "Update yt-dlp",
        updateChecking: "Checking…",
        updateUpToDateFormat: "yt-dlp %@ is already the newest.",
        updateInstalledFormat: "Updated yt-dlp to %@.",
        updateFailed: "Could not install the update.",
        updateCaption: "yt-dlp stops working when a site changes its player. Updating installs a build that Vorssaint did not sign and macOS did not notarize.",
        failureHelperMissingFormat: "The %@ helper is not installed.",
        failureHelperStale: "The site changed its player and the installed yt-dlp cannot follow it. Updating it usually helps.",
        failureVideoUnavailable: "That video is gone.",
        failureVideoPrivate: "That video is private.",
        failureMembersOnly: "That video needs a paid channel membership.",
        failureAgeRestricted: "That video needs a signed-in adult account.",
        failureGeoBlocked: "That video is not available in your country.",
        failureLiveNotFinished: "That stream has not finished yet.",
        failureNetwork: "Could not reach the site.",
        failureNotMedia: "That file has no audio Vorssaint can read.",
        failureDiskFull: "There is no room left on the disk.",
        failureRemoteUnreachable: "Could not reach your server.",
        failureRemoteRejectedFormat: "Your server answered with %lld.",
        failureCancelled: "Stopped.",
        failureHelperFailedFormat: "%@ stopped with code %lld. The log has the detail.",
        failureUnknown: "Something went wrong. The log has the detail."
    )

    static let ptBR = YouTubeTranscriberStrings(
        pageTitle: "Transcritor",
        hubDescription: "Transforma um link de vídeo ou um arquivo que você solta aqui em texto.",
        sourceLabel: "Link do vídeo ou arquivo",
        sourcePlaceholder: "Cole um link ou solte um arquivo de áudio ou vídeo",
        start: "Transcrever",
        cancel: "Parar",
        openTranscript: "Abrir transcrição",
        showInFinder: "Mostrar no Finder",
        copyTranscript: "Copiar transcrição",
        phaseReadingTitle: "Lendo o título",
        phaseDownloading: "Buscando o áudio",
        phaseMeasuring: "Medindo o áudio",
        phaseUploading: "Enviando",
        phaseTranscribing: "Transcrevendo",
        phaseFinished: "Pronto",
        locationLabel: "Transcrever",
        locationLocal: "Neste Mac",
        locationRemote: "Em um servidor seu",
        remoteHostLabel: "Servidor",
        remoteHostPlaceholder: "whisper.exemplo.com",
        remoteHostCaption: "Um servidor whisper.cpp seu. Sem esquema, a conexão usa https, então o áudio não viaja aberto.",
        keepAudio: "Manter o arquivo de áudio",
        keepAudioCaption: "O áudio extraído é apagado assim que a transcrição é salva.",
        outputFolder: "Salvar em",
        outputFolderCaption: "As transcrições vão para Downloads, a menos que você escolha outro lugar.",
        helpersSection: "Auxiliares",
        helpersMissingFormat: "Faltando: %@. A transcrição precisa deles.",
        helpersReady: "Todos os auxiliares estão instalados.",
        updateButton: "Atualizar o yt-dlp",
        updateChecking: "Verificando…",
        updateUpToDateFormat: "O yt-dlp %@ já é o mais recente.",
        updateInstalledFormat: "yt-dlp atualizado para %@.",
        updateFailed: "Não foi possível instalar a atualização.",
        updateCaption: "O yt-dlp para de funcionar quando um site muda o player. Atualizar instala um binário que o Vorssaint não assinou e a Apple não autenticou.",
        failureHelperMissingFormat: "O auxiliar %@ não está instalado.",
        failureHelperStale: "O site mudou o player e o yt-dlp instalado não acompanha. Atualizar costuma resolver.",
        failureVideoUnavailable: "Esse vídeo não existe mais.",
        failureVideoPrivate: "Esse vídeo é privado.",
        failureMembersOnly: "Esse vídeo exige uma assinatura paga do canal.",
        failureAgeRestricted: "Esse vídeo exige uma conta adulta conectada.",
        failureGeoBlocked: "Esse vídeo não está disponível no seu país.",
        failureLiveNotFinished: "Essa transmissão ainda não terminou.",
        failureNetwork: "Não foi possível acessar o site.",
        failureNotMedia: "Esse arquivo não tem áudio que o Vorssaint consiga ler.",
        failureDiskFull: "Não há mais espaço no disco.",
        failureRemoteUnreachable: "Não foi possível acessar o seu servidor.",
        failureRemoteRejectedFormat: "O seu servidor respondeu com %lld.",
        failureCancelled: "Parado.",
        failureHelperFailedFormat: "O %@ parou com o código %lld. O registro tem os detalhes.",
        failureUnknown: "Algo deu errado. O registro tem os detalhes."
    )

    static let tr = YouTubeTranscriberStrings(
        pageTitle: "Deşifre",
        hubDescription: "Bir video bağlantısını ya da bıraktığınız dosyayı metne çevirir.",
        sourceLabel: "Video bağlantısı veya dosya",
        sourcePlaceholder: "Bir bağlantı yapıştırın ya da ses veya video dosyası bırakın",
        start: "Deşifre et",
        cancel: "Durdur",
        openTranscript: "Metni aç",
        showInFinder: "Finder’da göster",
        copyTranscript: "Metni kopyala",
        phaseReadingTitle: "Başlık okunuyor",
        phaseDownloading: "Ses alınıyor",
        phaseMeasuring: "Ses ölçülüyor",
        phaseUploading: "Yükleniyor",
        phaseTranscribing: "Deşifre ediliyor",
        phaseFinished: "Bitti",
        locationLabel: "Deşifre yeri",
        locationLocal: "Bu Mac’te",
        locationRemote: "Kendi sunucunuzda",
        remoteHostLabel: "Sunucu",
        remoteHostPlaceholder: "whisper.ornek.com",
        remoteHostCaption: "Kendi whisper.cpp sunucunuz. Şema yazmazsanız https kullanılır, böylece ses açık gitmez.",
        keepAudio: "Ses dosyasını sakla",
        keepAudioCaption: "Metin yazıldıktan sonra çıkarılan ses silinir.",
        outputFolder: "Şuraya kaydet",
        outputFolderCaption: "Başka bir yer seçmezseniz metinler İndirilenler klasörüne gider.",
        helpersSection: "Yardımcılar",
        helpersMissingFormat: "Eksik: %@. Deşifre bunlara ihtiyaç duyar.",
        helpersReady: "Bütün yardımcılar kurulu.",
        updateButton: "yt-dlp’yi güncelle",
        updateChecking: "Bakılıyor…",
        updateUpToDateFormat: "yt-dlp %@ zaten en yenisi.",
        updateInstalledFormat: "yt-dlp %@ sürümüne güncellendi.",
        updateFailed: "Güncelleme kurulamadı.",
        updateCaption: "Bir site oynatıcısını değiştirdiğinde yt-dlp çalışmaz olur. Güncelleme, Vorssaint’in imzalamadığı ve Apple’ın onaylamadığı bir dosya kurar.",
        failureHelperMissingFormat: "%@ yardımcısı kurulu değil.",
        failureHelperStale: "Site oynatıcısını değiştirdi, kurulu yt-dlp yetişemiyor. Güncellemek genelde çözer.",
        failureVideoUnavailable: "O video artık yok.",
        failureVideoPrivate: "O video gizli.",
        failureMembersOnly: "O video ücretli kanal üyeliği istiyor.",
        failureAgeRestricted: "O video giriş yapmış bir yetişkin hesabı istiyor.",
        failureGeoBlocked: "O video ülkenizde açılmıyor.",
        failureLiveNotFinished: "O yayın daha bitmedi.",
        failureNetwork: "Siteye ulaşılamadı.",
        failureNotMedia: "O dosyada Vorssaint’in okuyabileceği ses yok.",
        failureDiskFull: "Diskte yer kalmadı.",
        failureRemoteUnreachable: "Sunucunuza ulaşılamadı.",
        failureRemoteRejectedFormat: "Sunucunuz %lld yanıtı verdi.",
        failureCancelled: "Durduruldu.",
        failureHelperFailedFormat: "%@ %lld koduyla durdu. Ayrıntı kayıtta.",
        failureUnknown: "Bir şeyler ters gitti. Ayrıntı kayıtta."
    )

    static let ru = YouTubeTranscriberStrings(
        pageTitle: "Расшифровка",
        hubDescription: "Превращает ссылку на видео или брошенный сюда файл в текст.",
        sourceLabel: "Ссылка на видео или файл",
        sourcePlaceholder: "Вставьте ссылку или перетащите аудио- или видеофайл",
        start: "Расшифровать",
        cancel: "Остановить",
        openTranscript: "Открыть текст",
        showInFinder: "Показать в Finder",
        copyTranscript: "Скопировать текст",
        phaseReadingTitle: "Читаем название",
        phaseDownloading: "Забираем звук",
        phaseMeasuring: "Измеряем звук",
        phaseUploading: "Отправляем",
        phaseTranscribing: "Расшифровываем",
        phaseFinished: "Готово",
        locationLabel: "Расшифровывать",
        locationLocal: "На этом Mac",
        locationRemote: "На вашем сервере",
        remoteHostLabel: "Сервер",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "Ваш собственный сервер whisper.cpp. Без схемы соединение идёт по https, поэтому звук не уходит открытым.",
        keepAudio: "Оставлять аудиофайл",
        keepAudioCaption: "Извлечённый звук удаляется, как только текст сохранён.",
        outputFolder: "Сохранять в",
        outputFolderCaption: "Расшифровки попадают в «Загрузки», если не выбрать другую папку.",
        helpersSection: "Вспомогательные программы",
        helpersMissingFormat: "Не хватает: %@. Без них расшифровка не работает.",
        helpersReady: "Все вспомогательные программы на месте.",
        updateButton: "Обновить yt-dlp",
        updateChecking: "Проверяем…",
        updateUpToDateFormat: "yt-dlp %@ и так самый свежий.",
        updateInstalledFormat: "yt-dlp обновлён до %@.",
        updateFailed: "Не удалось установить обновление.",
        updateCaption: "yt-dlp перестаёт работать, когда сайт меняет плеер. Обновление ставит файл, который Vorssaint не подписывал и Apple не заверяла.",
        failureHelperMissingFormat: "Программа %@ не установлена.",
        failureHelperStale: "Сайт поменял плеер, и установленный yt-dlp за ним не поспевает. Обычно помогает обновление.",
        failureVideoUnavailable: "Этого видео больше нет.",
        failureVideoPrivate: "Это видео приватное.",
        failureMembersOnly: "Это видео только для платных подписчиков канала.",
        failureAgeRestricted: "Для этого видео нужен вход во взрослый аккаунт.",
        failureGeoBlocked: "Это видео недоступно в вашей стране.",
        failureLiveNotFinished: "Эта трансляция ещё не закончилась.",
        failureNetwork: "Не удалось связаться с сайтом.",
        failureNotMedia: "В этом файле нет звука, который Vorssaint может прочитать.",
        failureDiskFull: "На диске не осталось места.",
        failureRemoteUnreachable: "Не удалось связаться с вашим сервером.",
        failureRemoteRejectedFormat: "Ваш сервер ответил кодом %lld.",
        failureCancelled: "Остановлено.",
        failureHelperFailedFormat: "%@ остановился с кодом %lld. Подробности в журнале.",
        failureUnknown: "Что-то пошло не так. Подробности в журнале."
    )

    static let es = YouTubeTranscriberStrings(
        pageTitle: "Transcriptor",
        hubDescription: "Convierte un enlace de vídeo o un archivo que sueltes aquí en texto.",
        sourceLabel: "Enlace del vídeo o archivo",
        sourcePlaceholder: "Pega un enlace o suelta un archivo de audio o vídeo",
        start: "Transcribir",
        cancel: "Parar",
        openTranscript: "Abrir la transcripción",
        showInFinder: "Mostrar en el Finder",
        copyTranscript: "Copiar la transcripción",
        phaseReadingTitle: "Leyendo el título",
        phaseDownloading: "Trayendo el audio",
        phaseMeasuring: "Midiendo el audio",
        phaseUploading: "Subiendo",
        phaseTranscribing: "Transcribiendo",
        phaseFinished: "Listo",
        locationLabel: "Transcribir",
        locationLocal: "En este Mac",
        locationRemote: "En un servidor tuyo",
        remoteHostLabel: "Servidor",
        remoteHostPlaceholder: "whisper.ejemplo.com",
        remoteHostCaption: "Un servidor whisper.cpp tuyo. Sin esquema se usa https, así el audio no viaja en claro.",
        keepAudio: "Conservar el archivo de audio",
        keepAudioCaption: "El audio extraído se borra en cuanto se guarda la transcripción.",
        outputFolder: "Guardar en",
        outputFolderCaption: "Las transcripciones van a Descargas salvo que elijas otro sitio.",
        helpersSection: "Auxiliares",
        helpersMissingFormat: "Faltan: %@. La transcripción los necesita.",
        helpersReady: "Todos los auxiliares están instalados.",
        updateButton: "Actualizar yt-dlp",
        updateChecking: "Comprobando…",
        updateUpToDateFormat: "yt-dlp %@ ya es el más reciente.",
        updateInstalledFormat: "yt-dlp actualizado a %@.",
        updateFailed: "No se pudo instalar la actualización.",
        updateCaption: "yt-dlp deja de funcionar cuando un sitio cambia su reproductor. Actualizar instala un binario que Vorssaint no firmó y Apple no notarizó.",
        failureHelperMissingFormat: "El auxiliar %@ no está instalado.",
        failureHelperStale: "El sitio cambió su reproductor y el yt-dlp instalado no lo sigue. Actualizarlo suele bastar.",
        failureVideoUnavailable: "Ese vídeo ya no existe.",
        failureVideoPrivate: "Ese vídeo es privado.",
        failureMembersOnly: "Ese vídeo exige una suscripción de pago al canal.",
        failureAgeRestricted: "Ese vídeo exige una cuenta adulta con la sesión iniciada.",
        failureGeoBlocked: "Ese vídeo no está disponible en tu país.",
        failureLiveNotFinished: "Esa emisión aún no ha terminado.",
        failureNetwork: "No se pudo llegar al sitio.",
        failureNotMedia: "Ese archivo no tiene audio que Vorssaint pueda leer.",
        failureDiskFull: "No queda espacio en el disco.",
        failureRemoteUnreachable: "No se pudo llegar a tu servidor.",
        failureRemoteRejectedFormat: "Tu servidor respondió con %lld.",
        failureCancelled: "Parado.",
        failureHelperFailedFormat: "%@ se detuvo con el código %lld. El registro tiene el detalle.",
        failureUnknown: "Algo salió mal. El registro tiene el detalle."
    )

    static let de = YouTubeTranscriberStrings(
        pageTitle: "Transkription",
        hubDescription: "Macht aus einem Videolink oder einer abgelegten Datei einen Text.",
        sourceLabel: "Videolink oder Datei",
        sourcePlaceholder: "Link einsetzen oder Audio- bzw. Videodatei ablegen",
        start: "Transkribieren",
        cancel: "Anhalten",
        openTranscript: "Transkript öffnen",
        showInFinder: "Im Finder zeigen",
        copyTranscript: "Transkript kopieren",
        phaseReadingTitle: "Titel wird gelesen",
        phaseDownloading: "Ton wird geholt",
        phaseMeasuring: "Ton wird vermessen",
        phaseUploading: "Wird hochgeladen",
        phaseTranscribing: "Wird transkribiert",
        phaseFinished: "Fertig",
        locationLabel: "Transkribieren",
        locationLocal: "Auf diesem Mac",
        locationRemote: "Auf einem eigenen Server",
        remoteHostLabel: "Server",
        remoteHostPlaceholder: "whisper.beispiel.de",
        remoteHostCaption: "Ein eigener whisper.cpp-Server. Ohne Schema wird https genommen, damit der Ton nicht offen übertragen wird.",
        keepAudio: "Audiodatei behalten",
        keepAudioCaption: "Der ausgelesene Ton wird gelöscht, sobald das Transkript geschrieben ist.",
        outputFolder: "Sichern unter",
        outputFolderCaption: "Transkripte landen in „Downloads“, solange nichts anderes gewählt ist.",
        helpersSection: "Hilfsprogramme",
        helpersMissingFormat: "Fehlt: %@. Ohne sie geht die Transkription nicht.",
        helpersReady: "Alle Hilfsprogramme sind installiert.",
        updateButton: "yt-dlp aktualisieren",
        updateChecking: "Wird geprüft…",
        updateUpToDateFormat: "yt-dlp %@ ist schon das neueste.",
        updateInstalledFormat: "yt-dlp auf %@ aktualisiert.",
        updateFailed: "Die Aktualisierung ließ sich nicht installieren.",
        updateCaption: "yt-dlp hört auf zu funktionieren, sobald eine Seite ihren Player ändert. Die Aktualisierung installiert eine Datei, die Vorssaint nicht signiert und Apple nicht notarisiert hat.",
        failureHelperMissingFormat: "Das Hilfsprogramm %@ ist nicht installiert.",
        failureHelperStale: "Die Seite hat ihren Player geändert, das installierte yt-dlp kommt nicht mit. Aktualisieren hilft meistens.",
        failureVideoUnavailable: "Dieses Video gibt es nicht mehr.",
        failureVideoPrivate: "Dieses Video ist privat.",
        failureMembersOnly: "Dieses Video braucht eine bezahlte Kanalmitgliedschaft.",
        failureAgeRestricted: "Dieses Video braucht ein angemeldetes Erwachsenenkonto.",
        failureGeoBlocked: "Dieses Video ist in Ihrem Land nicht verfügbar.",
        failureLiveNotFinished: "Diese Übertragung ist noch nicht zu Ende.",
        failureNetwork: "Die Seite war nicht erreichbar.",
        failureNotMedia: "In dieser Datei ist kein Ton, den Vorssaint lesen kann.",
        failureDiskFull: "Auf dem Volume ist kein Platz mehr.",
        failureRemoteUnreachable: "Ihr Server war nicht erreichbar.",
        failureRemoteRejectedFormat: "Ihr Server hat mit %lld geantwortet.",
        failureCancelled: "Angehalten.",
        failureHelperFailedFormat: "%@ endete mit Code %lld. Das Protokoll hat die Einzelheiten.",
        failureUnknown: "Da ging etwas schief. Das Protokoll hat die Einzelheiten."
    )

    static let fr = YouTubeTranscriberStrings(
        pageTitle: "Transcription",
        hubDescription: "Transforme un lien vidéo ou un fichier déposé ici en texte.",
        sourceLabel: "Lien vidéo ou fichier",
        sourcePlaceholder: "Collez un lien ou déposez un fichier audio ou vidéo",
        start: "Transcrire",
        cancel: "Arrêter",
        openTranscript: "Ouvrir la transcription",
        showInFinder: "Afficher dans le Finder",
        copyTranscript: "Copier la transcription",
        phaseReadingTitle: "Lecture du titre",
        phaseDownloading: "Récupération du son",
        phaseMeasuring: "Mesure du son",
        phaseUploading: "Envoi",
        phaseTranscribing: "Transcription",
        phaseFinished: "Terminé",
        locationLabel: "Transcrire",
        locationLocal: "Sur ce Mac",
        locationRemote: "Sur votre serveur",
        remoteHostLabel: "Serveur",
        remoteHostPlaceholder: "whisper.exemple.fr",
        remoteHostCaption: "Votre propre serveur whisper.cpp. Sans schéma, la connexion passe en https, donc le son ne circule pas en clair.",
        keepAudio: "Garder le fichier audio",
        keepAudioCaption: "Le son extrait est supprimé dès que la transcription est écrite.",
        outputFolder: "Enregistrer dans",
        outputFolderCaption: "Les transcriptions vont dans Téléchargements tant que vous ne choisissez pas autre chose.",
        helpersSection: "Utilitaires",
        helpersMissingFormat: "Manquant\u{00A0}: %@. La transcription en a besoin.",
        helpersReady: "Tous les utilitaires sont installés.",
        updateButton: "Mettre à jour yt-dlp",
        updateChecking: "Vérification…",
        updateUpToDateFormat: "yt-dlp %@ est déjà le plus récent.",
        updateInstalledFormat: "yt-dlp mis à jour vers %@.",
        updateFailed: "Impossible d’installer la mise à jour.",
        updateCaption: "yt-dlp cesse de fonctionner dès qu’un site change son lecteur. La mise à jour installe un fichier que Vorssaint n’a pas signé et qu’Apple n’a pas notarisé.",
        failureHelperMissingFormat: "L’utilitaire %@ n’est pas installé.",
        failureHelperStale: "Le site a changé son lecteur et le yt-dlp installé ne suit plus. Le mettre à jour suffit en général.",
        failureVideoUnavailable: "Cette vidéo n’existe plus.",
        failureVideoPrivate: "Cette vidéo est privée.",
        failureMembersOnly: "Cette vidéo demande un abonnement payant à la chaîne.",
        failureAgeRestricted: "Cette vidéo demande un compte adulte connecté.",
        failureGeoBlocked: "Cette vidéo n’est pas disponible dans votre pays.",
        failureLiveNotFinished: "Cette diffusion n’est pas terminée.",
        failureNetwork: "Le site est resté injoignable.",
        failureNotMedia: "Ce fichier ne contient aucun son que Vorssaint sache lire.",
        failureDiskFull: "Il n’y a plus de place sur le disque.",
        failureRemoteUnreachable: "Votre serveur est resté injoignable.",
        failureRemoteRejectedFormat: "Votre serveur a répondu %lld.",
        failureCancelled: "Arrêté.",
        failureHelperFailedFormat: "%@ s’est arrêté avec le code %lld. Le journal donne le détail.",
        failureUnknown: "Quelque chose a échoué. Le journal donne le détail."
    )

    static let it = YouTubeTranscriberStrings(
        pageTitle: "Trascrizione",
        hubDescription: "Trasforma in testo un link video o un file trascinato qui.",
        sourceLabel: "Link del video o file",
        sourcePlaceholder: "Incolla un link o trascina un file audio o video",
        start: "Trascrivi",
        cancel: "Ferma",
        openTranscript: "Apri la trascrizione",
        showInFinder: "Mostra nel Finder",
        copyTranscript: "Copia la trascrizione",
        phaseReadingTitle: "Lettura del titolo",
        phaseDownloading: "Recupero dell’audio",
        phaseMeasuring: "Misura dell’audio",
        phaseUploading: "Invio",
        phaseTranscribing: "Trascrizione",
        phaseFinished: "Fatto",
        locationLabel: "Trascrivi",
        locationLocal: "Su questo Mac",
        locationRemote: "Su un tuo server",
        remoteHostLabel: "Server",
        remoteHostPlaceholder: "whisper.esempio.it",
        remoteHostCaption: "Un tuo server whisper.cpp. Senza schema si usa https, così l’audio non viaggia in chiaro.",
        keepAudio: "Conserva il file audio",
        keepAudioCaption: "L’audio estratto viene eliminato appena la trascrizione è salvata.",
        outputFolder: "Salva in",
        outputFolderCaption: "Le trascrizioni finiscono in Download finché non scegli altro.",
        helpersSection: "Programmi di supporto",
        helpersMissingFormat: "Manca: %@. Senza non si trascrive.",
        helpersReady: "Tutti i programmi di supporto sono installati.",
        updateButton: "Aggiorna yt-dlp",
        updateChecking: "Controllo…",
        updateUpToDateFormat: "yt-dlp %@ è già il più recente.",
        updateInstalledFormat: "yt-dlp aggiornato a %@.",
        updateFailed: "Non è stato possibile installare l’aggiornamento.",
        updateCaption: "yt-dlp smette di funzionare quando un sito cambia il player. L’aggiornamento installa un file che Vorssaint non ha firmato e Apple non ha autenticato.",
        failureHelperMissingFormat: "Il programma %@ non è installato.",
        failureHelperStale: "Il sito ha cambiato il player e il yt-dlp installato non lo segue. Aggiornarlo di solito basta.",
        failureVideoUnavailable: "Quel video non c’è più.",
        failureVideoPrivate: "Quel video è privato.",
        failureMembersOnly: "Quel video richiede un abbonamento a pagamento al canale.",
        failureAgeRestricted: "Quel video richiede un account adulto collegato.",
        failureGeoBlocked: "Quel video non è disponibile nel tuo paese.",
        failureLiveNotFinished: "Quella diretta non è ancora finita.",
        failureNetwork: "Il sito è rimasto irraggiungibile.",
        failureNotMedia: "In quel file non c’è audio che Vorssaint sappia leggere.",
        failureDiskFull: "Sul disco non resta spazio.",
        failureRemoteUnreachable: "Il tuo server è rimasto irraggiungibile.",
        failureRemoteRejectedFormat: "Il tuo server ha risposto %lld.",
        failureCancelled: "Fermato.",
        failureHelperFailedFormat: "%@ si è fermato con codice %lld. Il registro ha il dettaglio.",
        failureUnknown: "Qualcosa è andato storto. Il registro ha il dettaglio."
    )

    static let ja = YouTubeTranscriberStrings(
        pageTitle: "文字起こし",
        hubDescription: "動画のリンクや置いたファイルを文字にします。",
        sourceLabel: "動画のリンクまたはファイル",
        sourcePlaceholder: "リンクを貼るか、音声・動画ファイルを置いてください",
        start: "文字起こし",
        cancel: "停止",
        openTranscript: "文字起こしを開く",
        showInFinder: "Finderで表示",
        copyTranscript: "文字起こしをコピー",
        phaseReadingTitle: "タイトルを読んでいます",
        phaseDownloading: "音声を取得しています",
        phaseMeasuring: "音声を測っています",
        phaseUploading: "アップロード中",
        phaseTranscribing: "文字起こし中",
        phaseFinished: "完了",
        locationLabel: "処理する場所",
        locationLocal: "このMac",
        locationRemote: "自分のサーバ",
        remoteHostLabel: "サーバ",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "自分で動かしているwhisper.cppサーバ。スキームを書かなければhttpsで接続するので、音声が平文で流れません。",
        keepAudio: "音声ファイルを残す",
        keepAudioCaption: "文字起こしを書き終えると、取り出した音声は削除されます。",
        outputFolder: "保存先",
        outputFolderCaption: "指定しなければ、文字起こしは「ダウンロード」に入ります。",
        helpersSection: "補助ツール",
        helpersMissingFormat: "不足: %@。文字起こしに必要です。",
        helpersReady: "補助ツールはすべて入っています。",
        updateButton: "yt-dlpを更新",
        updateChecking: "確認中…",
        updateUpToDateFormat: "yt-dlp %@ はすでに最新です。",
        updateInstalledFormat: "yt-dlpを %@ に更新しました。",
        updateFailed: "更新を入れられませんでした。",
        updateCaption: "サイトがプレーヤーを変えるとyt-dlpは動かなくなります。更新すると、Vorssaintが署名しておらずAppleの公証も受けていないファイルを入れることになります。",
        failureHelperMissingFormat: "補助ツール %@ が入っていません。",
        failureHelperStale: "サイトがプレーヤーを変え、入っているyt-dlpが追随できません。たいていは更新で直ります。",
        failureVideoUnavailable: "その動画はもうありません。",
        failureVideoPrivate: "その動画は非公開です。",
        failureMembersOnly: "その動画は有料のチャンネルメンバーシップが必要です。",
        failureAgeRestricted: "その動画はサインイン済みの成人アカウントが必要です。",
        failureGeoBlocked: "その動画はお住まいの国では見られません。",
        failureLiveNotFinished: "その配信はまだ終わっていません。",
        failureNetwork: "サイトに接続できませんでした。",
        failureNotMedia: "そのファイルにVorssaintが読める音声がありません。",
        failureDiskFull: "ディスクに空きがありません。",
        failureRemoteUnreachable: "サーバに接続できませんでした。",
        failureRemoteRejectedFormat: "サーバが %lld を返しました。",
        failureCancelled: "停止しました。",
        failureHelperFailedFormat: "%@ がコード %lld で止まりました。詳しくはログに出ています。",
        failureUnknown: "うまくいきませんでした。詳しくはログに出ています。"
    )

    static let ko = YouTubeTranscriberStrings(
        pageTitle: "받아쓰기",
        hubDescription: "동영상 링크나 끌어다 놓은 파일을 글로 바꿉니다.",
        sourceLabel: "동영상 링크 또는 파일",
        sourcePlaceholder: "링크를 붙여넣거나 오디오나 동영상 파일을 놓으세요",
        start: "받아쓰기",
        cancel: "중지",
        openTranscript: "받아쓴 글 열기",
        showInFinder: "Finder에서 보기",
        copyTranscript: "받아쓴 글 복사",
        phaseReadingTitle: "제목을 읽는 중",
        phaseDownloading: "소리를 가져오는 중",
        phaseMeasuring: "소리를 재는 중",
        phaseUploading: "올리는 중",
        phaseTranscribing: "받아쓰는 중",
        phaseFinished: "완료",
        locationLabel: "받아쓰는 곳",
        locationLocal: "이 Mac에서",
        locationRemote: "직접 운영하는 서버에서",
        remoteHostLabel: "서버",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "직접 운영하는 whisper.cpp 서버입니다. 스킴을 쓰지 않으면 https로 연결해 소리가 평문으로 오가지 않습니다.",
        keepAudio: "오디오 파일 남기기",
        keepAudioCaption: "받아쓴 글을 저장하면 뽑아낸 소리는 지웁니다.",
        outputFolder: "저장 위치",
        outputFolderCaption: "따로 고르지 않으면 받아쓴 글은 다운로드에 들어갑니다.",
        helpersSection: "보조 프로그램",
        helpersMissingFormat: "없음: %@. 받아쓰기에 필요합니다.",
        helpersReady: "보조 프로그램이 모두 설치되어 있습니다.",
        updateButton: "yt-dlp 업데이트",
        updateChecking: "확인하는 중…",
        updateUpToDateFormat: "yt-dlp %@ 이(가) 이미 최신입니다.",
        updateInstalledFormat: "yt-dlp를 %@ (으)로 업데이트했습니다.",
        updateFailed: "업데이트를 설치하지 못했습니다.",
        updateCaption: "사이트가 재생기를 바꾸면 yt-dlp는 멈춥니다. 업데이트하면 Vorssaint가 서명하지 않고 Apple이 공증하지 않은 파일을 설치하게 됩니다.",
        failureHelperMissingFormat: "보조 프로그램 %@ 이(가) 설치되어 있지 않습니다.",
        failureHelperStale: "사이트가 재생기를 바꿔서 설치된 yt-dlp가 따라가지 못합니다. 대개 업데이트하면 해결됩니다.",
        failureVideoUnavailable: "그 동영상은 이제 없습니다.",
        failureVideoPrivate: "그 동영상은 비공개입니다.",
        failureMembersOnly: "그 동영상은 유료 채널 멤버십이 필요합니다.",
        failureAgeRestricted: "그 동영상은 로그인한 성인 계정이 필요합니다.",
        failureGeoBlocked: "그 동영상은 이 나라에서 볼 수 없습니다.",
        failureLiveNotFinished: "그 방송은 아직 끝나지 않았습니다.",
        failureNetwork: "사이트에 닿지 못했습니다.",
        failureNotMedia: "그 파일에는 Vorssaint가 읽을 수 있는 소리가 없습니다.",
        failureDiskFull: "디스크에 남은 공간이 없습니다.",
        failureRemoteUnreachable: "서버에 닿지 못했습니다.",
        failureRemoteRejectedFormat: "서버가 %lld 로 답했습니다.",
        failureCancelled: "중지했습니다.",
        failureHelperFailedFormat: "%@ 이(가) 코드 %lld 로 멈췄습니다. 기록에 자세히 있습니다.",
        failureUnknown: "잘 되지 않았습니다. 기록에 자세히 있습니다."
    )

    static let zhHans = YouTubeTranscriberStrings(
        pageTitle: "转写",
        hubDescription: "把视频链接或拖进来的文件变成文字。",
        sourceLabel: "视频链接或文件",
        sourcePlaceholder: "粘贴链接，或拖入音频、视频文件",
        start: "开始转写",
        cancel: "停止",
        openTranscript: "打开文字稿",
        showInFinder: "在访达中显示",
        copyTranscript: "拷贝文字稿",
        phaseReadingTitle: "正在读取标题",
        phaseDownloading: "正在取音频",
        phaseMeasuring: "正在测量音频",
        phaseUploading: "正在上传",
        phaseTranscribing: "正在转写",
        phaseFinished: "完成",
        locationLabel: "转写位置",
        locationLocal: "在这台 Mac 上",
        locationRemote: "在你自己的服务器上",
        remoteHostLabel: "服务器",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "你自己运行的 whisper.cpp 服务器。不写协议就用 https 连接，音频不会明文传输。",
        keepAudio: "保留音频文件",
        keepAudioCaption: "写完文字稿后就删除取出的音频。",
        outputFolder: "存储到",
        outputFolderCaption: "不另选位置时，文字稿会放进「下载」。",
        helpersSection: "辅助程序",
        helpersMissingFormat: "缺少：%@。转写需要它们。",
        helpersReady: "辅助程序都已安装。",
        updateButton: "更新 yt-dlp",
        updateChecking: "正在检查…",
        updateUpToDateFormat: "yt-dlp %@ 已经是最新的。",
        updateInstalledFormat: "已把 yt-dlp 更新到 %@。",
        updateFailed: "无法安装更新。",
        updateCaption: "网站一改播放器，yt-dlp 就不能用了。更新会装上一个 Vorssaint 没有签名、苹果也没有公证的文件。",
        failureHelperMissingFormat: "辅助程序 %@ 没有安装。",
        failureHelperStale: "网站换了播放器，已装的 yt-dlp 跟不上。更新一般就好了。",
        failureVideoUnavailable: "这个视频已经没有了。",
        failureVideoPrivate: "这个视频是私享的。",
        failureMembersOnly: "这个视频需要付费的频道会员。",
        failureAgeRestricted: "这个视频需要已登录的成人账户。",
        failureGeoBlocked: "这个视频在你所在的国家看不了。",
        failureLiveNotFinished: "这场直播还没结束。",
        failureNetwork: "连不上这个网站。",
        failureNotMedia: "这个文件里没有 Vorssaint 能读的音频。",
        failureDiskFull: "磁盘没有空间了。",
        failureRemoteUnreachable: "连不上你的服务器。",
        failureRemoteRejectedFormat: "你的服务器返回了 %lld。",
        failureCancelled: "已停止。",
        failureHelperFailedFormat: "%@ 以代码 %lld 结束。详情在日志里。",
        failureUnknown: "出了点问题。详情在日志里。"
    )

    static let zhTW = YouTubeTranscriberStrings(
        pageTitle: "轉寫",
        hubDescription: "把影片連結或拖進來的檔案變成文字。",
        sourceLabel: "影片連結或檔案",
        sourcePlaceholder: "貼上連結，或拖入音訊、影片檔案",
        start: "開始轉寫",
        cancel: "停止",
        openTranscript: "打開文字稿",
        showInFinder: "在 Finder 中顯示",
        copyTranscript: "拷貝文字稿",
        phaseReadingTitle: "正在讀取標題",
        phaseDownloading: "正在取音訊",
        phaseMeasuring: "正在測量音訊",
        phaseUploading: "正在上傳",
        phaseTranscribing: "正在轉寫",
        phaseFinished: "完成",
        locationLabel: "轉寫位置",
        locationLocal: "在這台 Mac 上",
        locationRemote: "在你自己的伺服器上",
        remoteHostLabel: "伺服器",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "你自己執行的 whisper.cpp 伺服器。不寫通訊協定就用 https 連線，音訊不會明文傳送。",
        keepAudio: "保留音訊檔案",
        keepAudioCaption: "寫完文字稿後就刪掉取出的音訊。",
        outputFolder: "儲存到",
        outputFolderCaption: "沒有另選位置時，文字稿會放進「下載項目」。",
        helpersSection: "輔助程式",
        helpersMissingFormat: "缺少：%@。轉寫需要它們。",
        helpersReady: "輔助程式都已安裝。",
        updateButton: "更新 yt-dlp",
        updateChecking: "正在檢查…",
        updateUpToDateFormat: "yt-dlp %@ 已經是最新的。",
        updateInstalledFormat: "已把 yt-dlp 更新到 %@。",
        updateFailed: "無法安裝更新。",
        updateCaption: "網站一改播放器，yt-dlp 就不能用了。更新會裝上一個 Vorssaint 沒有簽署、Apple 也沒有公證的檔案。",
        failureHelperMissingFormat: "輔助程式 %@ 沒有安裝。",
        failureHelperStale: "網站換了播放器，已安裝的 yt-dlp 跟不上。更新通常就好了。",
        failureVideoUnavailable: "這部影片已經沒有了。",
        failureVideoPrivate: "這部影片是私人的。",
        failureMembersOnly: "這部影片需要付費的頻道會員。",
        failureAgeRestricted: "這部影片需要已登入的成人帳號。",
        failureGeoBlocked: "這部影片在你所在的國家看不到。",
        failureLiveNotFinished: "這場直播還沒結束。",
        failureNetwork: "連不上這個網站。",
        failureNotMedia: "這個檔案裡沒有 Vorssaint 讀得到的音訊。",
        failureDiskFull: "磁碟沒有空間了。",
        failureRemoteUnreachable: "連不上你的伺服器。",
        failureRemoteRejectedFormat: "你的伺服器回應了 %lld。",
        failureCancelled: "已停止。",
        failureHelperFailedFormat: "%@ 以代碼 %lld 結束。詳情在記錄裡。",
        failureUnknown: "出了點問題。詳情在記錄裡。"
    )

    static let zhHK = YouTubeTranscriberStrings(
        pageTitle: "轉寫",
        hubDescription: "把影片連結或拖進來的檔案變成文字。",
        sourceLabel: "影片連結或檔案",
        sourcePlaceholder: "貼上連結，或拖入音訊、影片檔案",
        start: "開始轉寫",
        cancel: "停止",
        openTranscript: "打開文字稿",
        showInFinder: "喺 Finder 顯示",
        copyTranscript: "拷貝文字稿",
        phaseReadingTitle: "正在讀取標題",
        phaseDownloading: "正在取音訊",
        phaseMeasuring: "正在量度音訊",
        phaseUploading: "正在上載",
        phaseTranscribing: "正在轉寫",
        phaseFinished: "完成",
        locationLabel: "轉寫位置",
        locationLocal: "喺這部 Mac 上",
        locationRemote: "喺你自己的伺服器上",
        remoteHostLabel: "伺服器",
        remoteHostPlaceholder: "whisper.example.com",
        remoteHostCaption: "你自己執行的 whisper.cpp 伺服器。冇寫通訊協定就用 https 連線，音訊唔會明文傳送。",
        keepAudio: "保留音訊檔案",
        keepAudioCaption: "寫完文字稿之後就刪走取出的音訊。",
        outputFolder: "儲存到",
        outputFolderCaption: "冇另揀位置時，文字稿會放入「下載項目」。",
        helpersSection: "輔助程式",
        helpersMissingFormat: "缺少：%@。轉寫需要佢哋。",
        helpersReady: "輔助程式都已安裝。",
        updateButton: "更新 yt-dlp",
        updateChecking: "正在檢查…",
        updateUpToDateFormat: "yt-dlp %@ 已經係最新嘅。",
        updateInstalledFormat: "已將 yt-dlp 更新到 %@。",
        updateFailed: "無法安裝更新。",
        updateCaption: "網站一改播放器，yt-dlp 就用唔到。更新會裝上一個 Vorssaint 冇簽署、Apple 亦冇公證的檔案。",
        failureHelperMissingFormat: "輔助程式 %@ 未安裝。",
        failureHelperStale: "網站換咗播放器，已安裝嘅 yt-dlp 跟唔上。更新通常就得。",
        failureVideoUnavailable: "呢條片已經冇咗。",
        failureVideoPrivate: "呢條片係私人嘅。",
        failureMembersOnly: "呢條片需要付費嘅頻道會員。",
        failureAgeRestricted: "呢條片需要已登入嘅成人帳戶。",
        failureGeoBlocked: "呢條片喺你所在嘅國家睇唔到。",
        failureLiveNotFinished: "呢場直播仲未完。",
        failureNetwork: "連唔到呢個網站。",
        failureNotMedia: "呢個檔案入面冇 Vorssaint 讀得到嘅音訊。",
        failureDiskFull: "磁碟冇空間喇。",
        failureRemoteUnreachable: "連唔到你嘅伺服器。",
        failureRemoteRejectedFormat: "你嘅伺服器回應咗 %lld。",
        failureCancelled: "已停止。",
        failureHelperFailedFormat: "%@ 以代碼 %lld 結束。詳情喺記錄裡面。",
        failureUnknown: "出咗少少問題。詳情喺記錄裡面。"
    )
}
