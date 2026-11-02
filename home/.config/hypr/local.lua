-- This laptop (Lenovo Legion): see local.lua.example in the dotfiles.
return {
	keyboard = {
		layout = "pl",
		-- Left Alt acts as Super and the other way round.
		options = "altwin:swap_lalt_lwin",
	},

	laptop = { output = "desc:BOE 0x0998" },

	-- `laptop`: where the panel goes while this monitor is connected. Under the
	-- 2560x1440 iiyama, centred ((2560 - 1920) / 2 = x 320), or left of the row
	-- of two 1920x1080 HPs.
	monitors = {
		{
			output = "desc:iiyama Corporation PL2792Q 1152011401936",
			position = "0x0",
			laptop = "320x1440",
		},
		{
			output = "desc:Hewlett Packard HP E231 6CM4310BTR",
			position = "0x0",
			laptop = "-1920x0",
		},
		{ output = "desc:Hewlett Packard HP E231 6CM3252T9W", position = "1920x0" },
	},

	-- The mic at +26 dB: the loudest laugh peaks at -1 dBFS, measured 2026-11-02; 0.3 clipped it.
	autostart = {
		"wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 0.27",
	},
}
