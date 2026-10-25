-- This laptop (Lenovo Legion): see local.lua.example in the dotfiles.
return {
	keyboard = {
		layout = "pl",
		-- Left Alt acts as Super and the other way round.
		options = "altwin:swap_lalt_lwin",
	},

	env = function(set)
		local igpu_first = "/dev/dri/amd-igpu:/dev/dri/nvidia-dgpu"
		local dgpu_first = "/dev/dri/nvidia-dgpu:/dev/dri/amd-igpu"

		-- External outputs are wired to the dGPU. Rendering them on the iGPU
		-- costs a cross-GPU copy per frame and forces software cursors, so the
		-- dGPU goes first whenever it has a display attached at session start;
		-- without one the iGPU renders and the dGPU can sleep (games go to it
		-- through dgpu-run). The order is fixed for the life of the session: a
		-- reload keeps the one Hyprland started with, and a relogin picks it again.
		local function dgpu_has_display()
			local f = io.popen(
				'card="$(readlink -f /dev/dri/nvidia-dgpu)" && '
					.. 'grep -lx connected /sys/class/drm/"${card##*/}"-*/status 2>/dev/null'
			)
			if f == nil then
				return false
			end
			local out = f:read("*a") or ""
			f:close()
			return out ~= ""
		end

		local devices = os.getenv("AQ_DRM_DEVICES")
		if devices ~= igpu_first and devices ~= dgpu_first then
			devices = dgpu_has_display() and dgpu_first or igpu_first
		end
		set("AQ_DRM_DEVICES", devices)

		-- Clients follow the compositor's GPU; pinning them to the other one
		-- brings the copy back per app. Both branches set every variable so a
		-- relogin overwrites what the previous session left in the systemd env.
		local on_dgpu = devices == dgpu_first
		local vulkan_icd = "/usr/share/vulkan/icd.d/" .. (on_dgpu and "nvidia_icd.json" or "radeon_icd.json")
		set("VK_DRIVER_FILES", vulkan_icd)
		set("VK_ICD_FILENAMES", vulkan_icd)
		set("LIBVA_DRIVER_NAME", on_dgpu and "nvidia" or "radeonsi")
	end,

	laptop = { output = "desc:BOE 0x0998", mode = "1920x1080@165" },

	-- `laptop`: where the panel goes while this monitor is connected. Left of
	-- the 2560x1440 iiyama with the bottom edges aligned (1440 - 1080 = y 360),
	-- or centred below the row of two 1920x1080 HPs.
	monitors = {
		{ output = "desc:iiyama Corporation PL2792Q 1152011401936", position = "0x0", laptop = "-1920x360" },
		{ output = "desc:Hewlett Packard HP E231 6CM4310BTR", position = "0x0", laptop = "960x1080" },
		{ output = "desc:Hewlett Packard HP E231 6CM3252T9W", position = "1920x0" },
	},

	autostart = {
		"wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 0.25",
	},
}
