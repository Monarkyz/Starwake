class_name Settings
## Réglages du joueur, gardés d'une session à l'autre.

const PATH := "user://settings.cfg"
const DEFAULT_ADDRESS := "127.0.0.1:24565"
const LOCALES: Array[String] = ["fr", "en"]

static var player_name: String = ""
static var address: String = DEFAULT_ADDRESS
static var locale: String = ""
static var hero: String = HeroDefs.DEFAULT_HERO


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_name = str(cfg.get_value("player", "name", ""))
		address = str(cfg.get_value("network", "address", DEFAULT_ADDRESS))
		locale = str(cfg.get_value("ui", "locale", ""))
		hero = str(cfg.get_value("player", "hero", HeroDefs.DEFAULT_HERO))
	if not HeroDefs.has_hero(hero):
		hero = HeroDefs.DEFAULT_HERO
	if not LOCALES.has(locale):
		locale = "fr" if OS.get_locale_language() == "fr" else "en"
	TranslationServer.set_locale(locale)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "hero", hero)
	cfg.set_value("network", "address", address)
	cfg.set_value("ui", "locale", locale)
	cfg.save(PATH)


static func set_locale(new_locale: String) -> void:
	locale = new_locale
	TranslationServer.set_locale(locale)
	save_settings()
