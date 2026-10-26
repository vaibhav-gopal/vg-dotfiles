# Guest isolation (core/isolation.nix), end to end: a machine made from the hosts' own modules, with
# a standard user, isolation and containers on, beside three neighbours: a LAN router, a tailnet peer
# (which also answers on MagicDNS's addresses) and an "internet" host. The guest reaches the internet
# and MagicDNS but not the LAN or the tailnet: from their shell, from a build (the daemon downloads as
# nixbld) and from a rootless container (their subordinate uids). They see only their own processes,
# can't read the admin's home, and their ssh sessions get a private /tmp. In Slurm (slurmdbd on
# MariaDB, as on jade) they have an account and see only their own jobs; the console refuses them
# (pam_access). A shared folder (core/shared.nix) is open to its members, whatever their umask, and
# to their containers given their groups; a non-member is refused. Every refusal has a control:
# root, or the admin, gets through.
# Not covered here: the Tenstorrent card's per-job ACL (it needs the card).
# Run: nix build -L ./nix#checks.x86_64-linux.isolation
# tend: vg-dotfiles/NixOS/Core
{ nixpkgs, modules, specialArgsFor }:
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;

  guest = "colleague";
  keys = import "${nixpkgs}/nixos/tests/ssh-keys.nix" pkgs;

  # what the hosts get from the master flake's table (nix/flake.nix)
  conf = {
    username = "vaibhav";
    inherit system;
    hostname = "machine";
    version = "26.05";
    homedirectory = "/home/vaibhav";
    nixType = "nixos";
  };

  # a neighbour: its addresses on one vlan (eth1), and an HTTP server on each port it answers
  neighbour = { vlan, v4, v6 ? [ ], ports }: {
    virtualisation.vlans = [ vlan ];
    networking.firewall.enable = false;
    networking.primaryIPAddress = lib.mkForce (lib.head v4).address;
    networking.primaryIPv6Address = lib.mkForce (if v6 == [ ] then "" else (lib.head v6).address);
    networking.interfaces.eth1 = {
      ipv4.addresses = lib.mkForce (map (a: { address = a.address; prefixLength = a.prefix; }) v4);
      ipv6.addresses = lib.mkForce (map (a: { address = a.address; prefixLength = a.prefix; }) v6);
    };
    systemd.services = lib.listToAttrs (map (port: lib.nameValuePair "serve-${toString port}" {
      wantedBy = [ "multi-user.target" ];
      # on ::, with IPv4 mapped in, so it answers on every address
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString port} --bind :: --directory /etc";
    }) ports);
  };

  # the guest's container: bash and coreutils (timeout), loaded with `podman load`
  image = pkgs.dockerTools.buildImage {
    name = "probe";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "probe-root";
      paths = [ pkgs.bashInteractive pkgs.coreutils ];
      pathsToLink = [ "/bin" ];
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "isolation";
  # the hosts' modules set nixpkgs.config and overlays, so each machine makes its own pkgs
  node.pkgsReadOnly = false;
  node.specialArgs = specialArgsFor conf;

  nodes = {
    machine = { lib, ... }: {
      imports = modules;

      core.headless.enable = true;
      core.headless.isolation.enable = true;
      modules.containers.enable = true;
      profiles.users.${guest} = { logins = [ "ssh" ]; linger = true; };
      core.headless.sshd.userKeys.${guest} = [ keys.snakeOilPublicKey ];
      # `everyone` (the guest and the admin) comes by default; `solo` leaves the admin out
      profiles.shared.solo = [ guest ];
      # sized for the VM: 2 CPUs, 3.5 of its 4 GiB for Slurm, of which logins and daemons keep 3
      modules.slurm = {
        enable = true;
        node = "CPUs=2 RealMemory=3600";
        login.memory = 1024;
      };

      # not what's tested, and heavy or in the way in a VM: the bootloader and firmware (the VM boots
      # its own kernel), the home layer (profiles.test.sh evaluates it), NetworkManager (the
      # addresses below are static) and the binary caches (unreachable: builds fetch from the neighbours)
      core.boot.enable = false;
      core.home.enable = false;
      core.internet.enable = false;
      nix.settings.substituters = lib.mkForce [ ];

      virtualisation = {
        vlans = [ 1 2 3 ];
        cores = 2;
        memorySize = 4096;
        diskSize = 4096;
      };
      # the hosts file's address for `machine` (Slurm finds its controller by name)
      networking.primaryIPAddress = lib.mkForce "192.168.1.1";
      networking.primaryIPv6Address = lib.mkForce "fd00:1::1";
      networking.interfaces = {
        # LAN
        eth1.ipv4.addresses = lib.mkForce [{ address = "192.168.1.1"; prefixLength = 24; }];
        eth1.ipv6.addresses = lib.mkForce [{ address = "fd00:1::1"; prefixLength = 64; }];
        # tailnet (as tailscale0 would have it, on-link here)
        eth2.ipv4.addresses = lib.mkForce [{ address = "100.64.0.1"; prefixLength = 10; }];
        eth2.ipv6.addresses = lib.mkForce [{ address = "fd7a:115c:a1e0::1"; prefixLength = 48; }];
        # internet (TEST-NET-3: in none of the blocked ranges)
        eth3.ipv4.addresses = lib.mkForce [{ address = "203.0.113.1"; prefixLength = 24; }];
        eth3.ipv6.addresses = lib.mkForce [ ];
      };
    };

    router = neighbour {
      vlan = 1;
      v4 = [{ address = "192.168.1.2"; prefix = 24; }];
      v6 = [{ address = "fd00:1::2"; prefix = 64; }];
      ports = [ 80 ];
    };
    # sshd's port, and DNS on MagicDNS's addresses (the guests' one way into the tailnet ranges)
    peer = neighbour {
      vlan = 2;
      v4 = [{ address = "100.64.0.2"; prefix = 10; } { address = "100.100.100.100"; prefix = 32; }];
      v6 = [{ address = "fd7a:115c:a1e0::2"; prefix = 48; } { address = "fd7a:115c:a1e0::53"; prefix = 128; }];
      ports = [ 22 53 ];
    };
    internet = neighbour {
      vlan = 3;
      v4 = [{ address = "203.0.113.2"; prefix = 24; }];
      ports = [ 80 ];
    };
  };

  testScript = ''
    import shlex

    guest = "${guest}"
    to_lan = [("192.168.1.2", 80), ("fd00:1::2", 80)]
    to_tailnet = [("100.64.0.2", 22), ("fd7a:115c:a1e0::2", 22)]
    to_dns = [("100.100.100.100", 53), ("fd7a:115c:a1e0::53", 53)]
    to_internet = [("203.0.113.2", 80)]

    def reach(host, port):
        return f"timeout 5 bash -c 'exec 3<>/dev/tcp/{host}/{port}'"

    def as_user(user, cmd):
        # from /: runuser keeps the cwd, and a guest can't enter root's home
        return f"cd / && runuser -u {user} -- env HOME=/home/{user} XDG_RUNTIME_DIR=/run/user/{uid} bash -c {shlex.quote(cmd)}"

    def as_guest(cmd):
        return as_user(guest, cmd)

    start_all()
    for n in [router, peer, internet]:
        n.wait_for_unit("multi-user.target")
    router.wait_for_open_port(80)
    peer.wait_for_open_port(22)
    peer.wait_for_open_port(53)
    internet.wait_for_open_port(80)
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("firewall.service")
    uid = machine.succeed(f"id -u {guest}").strip()

    with subtest("controls: root and the admin reach every neighbour"):
        for host, port in to_lan + to_tailnet + to_dns + to_internet:
            machine.wait_until_succeeds(reach(host, port), timeout=60)
            machine.succeed(as_user("vaibhav", reach(host, port)))

    with subtest("the guest reaches the internet and MagicDNS, not the LAN or the tailnet"):
        for host, port in to_internet + to_dns:
            machine.succeed(as_guest(reach(host, port)))
        for host, port in to_lan + to_tailnet:
            machine.fail(as_guest(reach(host, port)))

    with subtest("a guest's build can't fetch from the LAN (the daemon downloads as nixbld)"):
        # a wrong hash: a download that arrives fails on the hash, a refused one on the connection
        def fetch(url, name):
            expr = f'import <nix/fetchurl.nix> {{ url = "{url}"; name = "{name}"; hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; }}'
            return machine.fail(as_guest(f"nix-build --no-out-link -E {shlex.quote(expr)} 2>&1"))
        out = fetch("http://203.0.113.2/hostname", "probe-internet")
        assert "hash mismatch" in out, f"control: the build should reach the internet host:\n{out}"
        out = fetch("http://192.168.1.2/hostname", "probe-lan")
        assert "hash mismatch" not in out and "connect" in out.lower(), f"the build reached the LAN:\n{out}"

    with subtest("a guest's rootless containers can't reach the LAN or the tailnet"):
        machine.wait_for_unit(f"user@{uid}.service")
        machine.succeed(as_guest("podman load -i ${image}"))
        # the guest themselves, and an image's own user (a subordinate uid and gid: with gid 0 inside,
        # the guest's own group, the group rule alone would catch it)
        for user in ["0:0", "1000:1000"]:
            def pod(cmd):
                return as_guest(f"podman run --rm --pull=never --network host --user {user} localhost/probe:latest bash -c {shlex.quote(cmd)}")
            machine.succeed(pod(reach(*to_internet[0])))
            machine.succeed(pod(reach(*to_dns[0])))
            for host, port in to_lan + to_tailnet:
                machine.fail(pod(reach(host, port)))

    with subtest("the guest sees only their own processes"):
        users = machine.succeed(as_guest("ps -e -o user=")).split()
        assert users and set(users) == {guest}, f"the guest sees {sorted(set(users))}"
        assert len(machine.succeed("ps -e -o user=").split()) > len(users) + 20

    with subtest("the guest can't read the admin's home, nor others' /tmp instances"):
        machine.fail(as_guest("ls /home/vaibhav"))
        machine.succeed("[ \"$(stat -c '%a %U' /var/lib/guest-tmp)\" = '0 root' ]")

    with subtest("the guest logs in over ssh, to a private /tmp"):
        machine.succeed("echo admin > /tmp/admins-file")
        router.succeed("install -m600 ${keys.snakeOilPrivateKey} /root/key")
        # -n: ssh would otherwise read stdin, the driver's own channel to the VM, and now and then
        # swallow a command's exit code ("invalid literal for int()", once in CI)
        ssh = f"ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /root/key {guest}@192.168.1.1"
        router.succeed(f"{ssh} 'test ! -e /tmp/admins-file && echo mine > /tmp/guests-file'")
        machine.fail("test -e /tmp/guests-file")
        machine.succeed("cat /var/lib/guest-tmp/tmp-*/guests-file | grep -qx mine")

    with subtest("a shared folder: its members share files, whatever their umask; others are refused"):
        machine.succeed(as_guest("umask 077 && mkdir /srv/shared/everyone/proj && echo v1 > /srv/shared/everyone/proj/notes"))
        machine.succeed(as_user("vaibhav", "echo v2 >> /srv/shared/everyone/proj/notes && touch /srv/shared/everyone/proj/more"))
        machine.succeed("[ \"$(stat -c %G /srv/shared/everyone/proj/more)\" = shared-everyone ]")
        machine.succeed(as_guest("grep -qx v2 /srv/shared/everyone/proj/notes"))
        machine.succeed(as_guest("touch /srv/shared/solo/mine"))  # control: a member gets in
        machine.fail(as_user("vaibhav", "ls /srv/shared/solo"))  # the admin isn't a member
        # a rootless container sees the folder only with the guest's groups passed in
        def pod_ls(extra):
            return as_guest(f"podman run --rm --pull=never {extra} -v /srv/shared/everyone:/data localhost/probe:latest ls /data/proj")
        machine.succeed(pod_ls("--group-add keep-groups"))
        machine.fail(pod_ls(""))

    with subtest("Slurm: the guest has an account, runs jobs, and sees only their own"):
        machine.wait_until_succeeds("sacctmgr -n show assoc user=colleague format=account | grep -qw colleagues", timeout=180)
        machine.wait_until_succeeds("sinfo -h -o %t | grep -qx idle", timeout=120)
        machine.succeed(as_guest("srun --mem=100M -c1 true"))
        job = machine.succeed(as_user("vaibhav", "sbatch --parsable --mem=100M -c1 --wrap 'sleep 600'")).strip()
        machine.wait_until_succeeds(f"squeue -h -j {job} -o %T | grep -qx RUNNING", timeout=60)
        machine.succeed(f"squeue -h -o %i | grep -qx {job}")  # control: root sees it
        machine.succeed(as_user("vaibhav", f"squeue -h -o %i | grep -qx {job}"))  # and the admin
        assert machine.succeed(as_guest("squeue -h -o %u")).strip() == "", "the guest sees others' jobs"
        machine.succeed(f"scancel {job}")

    with subtest("the console refuses the guest, and lets the admin in"):
        machine.succeed("echo 'colleague:guest-pw' | chpasswd", "echo 'vaibhav:admin-pw' | chpasswd")
        machine.wait_for_unit("getty@tty1.service")
        machine.wait_until_tty_matches("1", "login: ")
        machine.send_chars("colleague\n")
        machine.wait_until_tty_matches("1", "Password: ")
        machine.send_chars("guest-pw\n")
        # the password is right: the refusal is pam_access's (login shows it only for a moment)
        machine.wait_until_succeeds("journalctl -b -t login | grep -q \"pam_access(login:account): access denied for user .colleague. from .tty1.\"", timeout=60)
        machine.fail("loginctl list-sessions --no-legend | grep -w colleague | grep -w tty1")
        machine.send_key("alt-f2")
        machine.wait_until_succeeds("[ $(fgconsole) = 2 ]")
        machine.wait_for_unit("getty@tty2.service")
        machine.wait_until_tty_matches("2", "login: ")
        machine.send_chars("vaibhav\n")
        machine.wait_until_tty_matches("2", "Password: ")
        machine.send_chars("admin-pw\n")
        machine.wait_until_succeeds("loginctl list-sessions --no-legend | grep -w vaibhav | grep -qw tty2")
  '';
}
