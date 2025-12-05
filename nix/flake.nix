{
  description = "A Nix Flake for an xfce-based system with YubiKey setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    hm.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = {
    self,
    nixpkgs,
    hm,
  }: let
    mkSystem = system:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${hm}/nixos"
          "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
          "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
          (
            {
              lib,
              pkgs,
              config,
              ...
            }: let
              gpgAgentConf = pkgs.runCommand "gpg-agent.conf" {} ''
                sed '/pinentry-program/d' ${self}/../config/gpg-agent.conf > $out
                echo "pinentry-program ${pkgs.pinentry.curses}/bin/pinentry" >> $out
              '';

              /* should not be needed anymore
              shortcutHtml = pkgs.makeDesktopItem {
                name = "yubikey-guide-html";
                icon = "${pkgs.yubikey-manager-qt}/share/ykman-gui/icons/ykman.png";
                desktopName = "drduh's YubiKey Guide (html)";
                genericName = "Guide to using YubiKey for GPG and SSH (html)";
                comment = "Open the guide in a browser";
                categories = ["Documentation"];
                exec = "${viewYubikeyGuideHtml}/bin/view-yubikey-guide-html";
              };
              yubikeyGuideHtml = pkgs.symlinkJoin {
                name = "yubikey-guide-html";
                paths = [viewYubikeyGuideHtml shortcutHtml];
              };

              viewYubikeyGuideHtml = let
                guide = pkgs.stdenv.mkDerivation {
                  name = "yubikey-guide.html";
                  src = self;
                  buildInputs = [pkgs.pandoc];
                  installPhase = ''
                    pandoc --highlight-style pygments -s --toc README.md | \
                    sed -e 's/<keyid>/\&lt;keyid\&gt;/g' > $out
                  '';
                };
              in
                pkgs.writeShellScriptBin "view-yubikey-guide-html" ''
                  exec $(exo-open --launch WebBrowser ${guide} || true)
                '';
	      */

              viewYubikeyGuide = pkgs.writeShellScriptBin "view-yubikey-guide" ''
                viewer="$(type -P xdg-open || true)"
                if [ -z "$viewer" ]; then
                  viewer="${pkgs.glow}/bin/glow -p"
                fi
                exec $viewer "${self}/../README.md"
              '';
              shortcut = pkgs.makeDesktopItem {
                name = "yubikey-guide";
                icon = "${pkgs.yubioath-flutter}/share/icons/com.yubico.yubioath.png";
                desktopName = "YubiKey Guide";
                genericName = "Guide to using YubiKey for GnuPG and SSH";
                comment = "Open YubiKey Guide in a reader program";
                categories = ["Documentation"];
                exec = "${viewYubikeyGuide}/bin/view-yubikey-guide";
              };
              yubikeyGuide = pkgs.symlinkJoin {
                name = "yubikey-guide";
                paths = [viewYubikeyGuide shortcut];
              };
            in {
              isoImage = {
                isoName = "yubikeyLive.iso";
                # As of writing, zstd-based iso is 1542M, takes ~2mins to
                # compress. If you prefer a smaller image and are happy to
                # wait, delete the line below, it will default to a
                # slower-but-smaller xz (1375M in 8mins as of writing).
                squashfsCompression = "zstd";

                appendToMenuLabel = " YubiKey Live ${self.lastModifiedDate}";
                makeEfiBootable = true; # EFI booting
                makeUsbBootable = true; # USB booting
              };

              swapDevices = [];

              boot = {
                tmp.cleanOnBoot = true;
                kernel.sysctl = {"kernel.unprivileged_bpf_disabled" = 1;};
              };

              services = {
	        udisks2 = {
		  enable = true;
		  mountOnMedia = true;
		};
                pcscd.enable = true;
                udev.packages = [pkgs.yubikey-personalization];
                # Automatically log in at the virtual consoles.
                getty.autologinUser = "nixos";
                # Comment out to run in a console for a smaller iso and less RAM.
                xserver = {
                  enable = true;
                  desktopManager.xfce = {
                    enable = true;
                    enableScreensaver = false;
                  };
                  displayManager = {
                    lightdm.enable = true;
                  };
                };
                displayManager = {
                  autoLogin = {
                    enable = true;
                    user = "nixos";
                  };
                };
              };

              programs = {
                ssh.startAgent = false;
                gnupg = {
                  dirmngr.enable = true;
                  agent = {
                    enable = true;
                    enableSSHSupport = true;
                  };
                };
              };

              # Use less privileged nixos user
              users.users = {
                nixos = {
                  isNormalUser = true;
                  extraGroups = ["wheel" "video"];
                  initialHashedPassword = "";
                };
                root.initialHashedPassword = "";
              };

              home-manager.users.nixos = {pkgs, ...}: {
                xdg.mimeApps.defaultApplications = {
                  "x-scheme-handler/http" = ["xfce4-web-browser.desktop"];
                  "x-scheme-handler/https" = ["xfce4-web-browser.desktop"];
                };

                xdg.mimeApps.associations.added = {
                  "x-scheme-handler/http" = ["xfce4-web-browser.desktop"];
                  "x-scheme-handler/https" = ["xfce4-web-browser.desktop"];
                };

                xdg.configFile."xfce4/helpers.rc".text = ''
                  WebBrowser=custom-WebBrowser
                '';

                xdg.dataFile."xfce4/helpers/custom-WebBrowser.desktop".text = ''
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=netsurf-gtk3 "%s"
Icon=netsurf-gtk3
Name=netsurf-gtk3
X-XFCE-Commands=netsurf-gtk3
                '';

                # The state version is required and should stay at the version yubioath-flutter
                # originally installed.
                home.stateVersion = "25.05";
              };

              security = {
                pam.services.lightdm.text = ''
                  auth sufficient pam_succeed_if.so user ingroup wheel
                '';
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
              };

              environment.etc."mimedebug".source = pkgs.writeShellScriptBin "query-mime" ''
                XDG_UTILS_DEBUG_LEVEL=2 xdg-mime query default text/html
                ls /run/current-system/sw/share/applications
                mimeo --help
              '';

              environment.systemPackages = with pkgs; [
                # Tools for backing up keys
                paperkey
                pgpdump
                parted
                cryptsetup

                # Yubico's official tools
                yubikey-manager
                yubikey-personalization
                yubikey-personalization-gui
                yubico-piv-tool
                yubioath-flutter

                # Testing
                ent
                #haskellPackages.hopenpgp-tools

                # Password generation tools
                diceware
                pwgen

                # Might be useful beyond the scope of the guide
                cfssl
                pcsctools
                tmux
                htop
		age-plugin-yubikey

                # This guide itself (run `view-yubikey-guide` on the terminal
                # to open it in a non-graphical environment).
                yubikeyGuide
                #yubikeyGuideHtml

                # PDF and Markdown viewer
                kdePackages.okular

                # html files
                mimeo
                netsurf.browser
		keepassxc
		keepass-qrcodeview
	#	ungoogled-chromium
	#	firefox-bin
              ];

              # Disable networking so the system is air-gapped
              # Comment all of these lines out if you'll need internet access
#              boot.initrd.network.enable = false;
              networking = {
#                resolvconf.enable = false;
#                dhcpcd.enable = false;
                dhcpcd.allowInterfaces = [ "enp0s25" ];
#                interfaces = {};
                firewall.enable = true;
#                useDHCP = false;
#                useNetworkd = false;
                wireless.enable = false;
                networkmanager.enable = lib.mkForce false;
              };

              # Unset history so it's never stored Set GNUPGHOME to an
              # ephemeral location and configure GPG with the guide

              environment.interactiveShellInit = ''
                unset HISTFILE
                export GNUPGHOME="/run/user/$(id -u)/gnupg"
                if [ ! -d "$GNUPGHOME" ]; then
                  echo "Creating \$GNUPGHOME…"
                  install --verbose -m=0700 --directory="$GNUPGHOME"
                fi
                [ ! -f "$GNUPGHOME/gpg.conf" ] && cp --verbose "${self}/../config/gpg.conf" "$GNUPGHOME/gpg.conf"
                [ ! -f "$GNUPGHOME/gpg-agent.conf" ] && cp --verbose ${gpgAgentConf} "$GNUPGHOME/gpg-agent.conf"
                echo "\$GNUPGHOME is \"$GNUPGHOME\""
              '';

              # Copy the contents of contrib to the home directory, add a
              # shortcut to the guide on the desktop, and link to the whole
              # repo in the documents folder.
              system.activationScripts.yubikeyGuide = let
                homeDir = "/home/nixos/";
                desktopDir = homeDir + "Desktop/";
                documentsDir = homeDir + "Documents/";
              in ''
                mkdir -p ${desktopDir} ${documentsDir}
                chown nixos ${homeDir} ${desktopDir} ${documentsDir}

                cp -R ${self}/contrib/* ${homeDir}
                ln -sf ${yubikeyGuide}/share/applications/yubikey-guide.desktop ${desktopDir}
                ln -sfT ${self} ${documentsDir}/YubiKey-Guide
                #ln -sf $ { yubikeyGuideHtml }/share/applications/yubikey-guide-html.desktop ${desktopDir}
              '';
              system.stateVersion = "25.05";
              #system.activationScripts.base-dirs = {
              #  text = ''
              #    mkdir -p /nix/var/nix/profiles/per-user/nixos
              #  '';
              #};
            }
          )
        ];
      };
  in {
    nixosConfigurations.yubikeyLive.x86_64-linux = mkSystem "x86_64-linux";
    nixosConfigurations.yubikeyLive.aarch64-linux = mkSystem "aarch64-linux";
    formatter.x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
    formatter.aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
  };
}
