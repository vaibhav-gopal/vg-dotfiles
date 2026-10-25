# Slurm as a one-node cluster on a shared box: it schedules the cores, memory and Tenstorrent cards
# between the owner and the standard users (profiles.users), with fairshare priority from
# slurmdbd accounting on a local MariaDB.
# Access is gated, not advisory: the cards are root-only until a job is given one (the prolog adds
# the job user's ACL, the epilog takes it back, kills what still holds the card and clears the
# user's 1G hugepage files), and login sessions (user.slice) get a capped share of CPU and memory.
# Secrets are made on the host, never in the store: the munge key and the database password are
# generated at first boot under /etc/munge and /var/lib/slurmdbd.
# tend: vg-dotfiles/NixOS/Slurm
{ config, lib, pkgs, usrlib, username, ... }:
let
  cfg = config.modules.slurm;
  tt = config.modules.tenstorrent;
  host = config.networking.hostName;
  slurmConf = "${config.services.slurm.etcSlurm}/slurm.conf";
  slurm = config.services.slurm.package;
  account = "colleagues";
  members = [ username ] ++ config.profiles.standard;
  cards = lib.optionals tt.enable (map toString (lib.range 0 (cfg.cards - 1)));
  # memory kept out of jobs: the login sessions, the cards' 1G hugepages and the daemons (MiB)
  reservedMemory = cfg.login.memory + (if tt.enable then tt.hugepages * 1024 else 0) + 2048;

  # the system's wrapped Slurm tools, found at run time: slurm.conf names the prolog and epilog, so
  # they can't name slurm.conf (or the wrappers that carry it)
  scriptPath = "export PATH=/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.coreutils pkgs.findutils ]}";

  # the card indices a job holds, from its detailed record (GRES=tt:p150a:1(IDX:0) or IDX:0-1,3).
  # Only a running job's record carries IDX (a finished one prints GRES=tt:p150a:1), so the prolog
  # reads it and keeps the list in cardsDir for the epilog.
  cardsDir = "/run/slurm-tt";
  jobCards = ''
    job_cards() {
      scontrol show job -d "$SLURM_JOB_ID" \
        | ${pkgs.gnugrep}/bin/grep -o 'tt[^ ]*(IDX:[0-9,-]*)' \
        | ${pkgs.gnused}/bin/sed 's/.*IDX:\([0-9,-]*\))/\1/' | tr ',' '\n' \
        | while IFS=- read -r from to; do seq "$from" "''${to:-$from}"; done
    }
  '';
  prolog = pkgs.writeShellScript "slurm-prolog" ''
    set -eu
    ${scriptPath}
    ${jobCards}
    install -d -m 0700 ${cardsDir}
    job_cards >"${cardsDir}/$SLURM_JOB_ID"
    for i in $(cat "${cardsDir}/$SLURM_JOB_ID"); do
      ${pkgs.acl}/bin/setfacl -m "u:$SLURM_JOB_USER:rw" "/dev/tenstorrent/$i"
    done
  '';
  epilog = pkgs.writeShellScript "slurm-epilog" ''
    set -u
    ${scriptPath}
    for i in $(cat "${cardsDir}/$SLURM_JOB_ID" 2>/dev/null); do
      ${pkgs.acl}/bin/setfacl -x "u:$SLURM_JOB_USER" "/dev/tenstorrent/$i"
      # an fd opened during the job outlives the ACL: the card is free only once nothing holds it
      ${pkgs.psmisc}/bin/fuser -k -s "/dev/tenstorrent/$i" || true
    done
    rm -f "${cardsDir}/$SLURM_JOB_ID"
    # their hugepage files, unless another of their jobs is still running
    if [ -z "$(squeue -h -u "$SLURM_JOB_USER" -t RUNNING -o %i)" ]; then
      find /dev/hugepages-1G -maxdepth 1 -user "$SLURM_JOB_USER" -delete 2>/dev/null || true
    fi
    exit 0
  '';
in {
  options.modules.slurm = {
    enable = usrlib.mkEnableOptionFalse "Slurm on this host as a one-node cluster (controller, node, accounting)";
    node = usrlib.mkStringOption "This node's hardware as `slurmd -C` prints it, without NodeName (CPUs=... RealMemory=...)" "";
    cards = usrlib.mkIntOption "Tenstorrent cards Slurm hands out as the `tt` GRES (/dev/tenstorrent/0..)" 1;
    cardType = usrlib.mkStringOption "The cards' GRES type (`--gres=tt:<type>:1`)" "p150a";
    defaultTime = usrlib.mkStringOption "Time limit of a job that asks for none" "1:00:00";
    maxTime = usrlib.mkStringOption "Longest time limit a job may ask for" "2-00:00:00";
    login = {
      cpus = usrlib.mkIntOption "CPUs' worth of time all login sessions share (user.slice CPUQuota)" 2;
      memory = usrlib.mkIntOption "MiB all login sessions share (user.slice MemoryMax)" 8192;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.node != "";
      message = "modules.slurm.node: set it from `slurmd -C` on ${host} (CPUs=... Boards=... RealMemory=...)";
    }];

    services.slurm = {
      server.enable = true;
      client.enable = true;
      controlMachine = host;
      clusterName = host;
      procTrackType = "proctrack/cgroup";
      nodeName = [
        "${host} ${cfg.node} MemSpecLimit=${toString reservedMemory}${lib.optionalString tt.enable " Gres=tt:${cfg.cardType}:${toString cfg.cards}"} State=UNKNOWN"
      ];
      partitionName = [
        "main Nodes=${host} Default=YES DefaultTime=${cfg.defaultTime} MaxTime=${cfg.maxTime} State=UP"
      ];
      extraConfig = ''
        SchedulerType=sched/backfill
        SelectType=select/cons_tres
        SelectTypeParameters=CR_Core_Memory
        # a job that asks for no memory gets 2 GiB per CPU, not the whole node (which blocks everyone)
        DefMemPerCPU=2048
        TaskPlugin=task/cgroup,task/affinity
        JobAcctGatherType=jobacct_gather/cgroup
        ${lib.optionalString tt.enable "GresTypes=tt"}
        AccountingStorageType=accounting_storage/slurmdbd
        AccountingStorageHost=${host}
        AccountingStorageEnforce=associations,limits,qos
        ${lib.optionalString tt.enable "AccountingStorageTRES=gres/tt"}
        PriorityType=priority/multifactor
        PriorityDecayHalfLife=7-0
        PriorityWeightFairshare=10000
        PriorityWeightAge=1000
        PriorityWeightJobSize=100
        PrologFlags=Alloc,Contain
        Prolog=${prolog}
        Epilog=${epilog}
        # each job gets its own /tmp and /dev/shm (job_container.conf), removed when it ends
        NamespaceType=namespace/tmpfs
        # users see only their own jobs (sinfo still shows the node busy); the owner is a Slurm admin
        PrivateData=jobs
      '';
      extraCgroupConfig = ''
        ConstrainCores=yes
        ConstrainRAMSpace=yes
        ConstrainDevices=yes
      '';
      extraConfigPaths = [
        (pkgs.writeTextDir "job_container.conf" ''
          BasePath=/var/lib/slurm-tmp AutoBasePath=true Dirs=/tmp,/dev/shm
        '')
      ] ++ lib.optional tt.enable (pkgs.writeTextDir "gres.conf" ''
        Name=tt Type=${cfg.cardType} File=/dev/tenstorrent/[0-${toString (cfg.cards - 1)}]
      '');
      dbdserver = {
        enable = true;
        storagePassFile = "/var/lib/slurmdbd/storage-pass";
      };
    };

    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      # slurmdbd is its only client, on this host
      settings.mysqld.bind-address = "127.0.0.1";
      ensureDatabases = [ "slurm_acct_db" ];
      ensureUsers = [{
        name = "slurm";
        ensurePermissions."slurm_acct_db.*" = "ALL PRIVILEGES";
      }];
    };

    # the cards are root-only outside a job (tt-kmd's own rule makes them 0666); jobs get an ACL
    services.udev.extraRules = lib.mkIf tt.enable ''
      SUBSYSTEM=="tenstorrent", MODE="0600"
    '';

    # login sessions share a capped slice; jobs run under slurmd (system.slice), outside it
    systemd.slices.user.sliceConfig = {
      CPUQuota = "${toString (cfg.login.cpus * 100)}%";
      MemoryMax = "${toString cfg.login.memory}M";
    };

    systemd.services = {
      # the cluster's munge key, made once on this host
      munge-key = {
        description = "Create the munge key";
        wantedBy = [ "munged.service" ];
        before = [ "munged.service" ];
        unitConfig.ConditionPathExists = "!${config.services.munge.password}";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p "$(dirname ${config.services.munge.password})"
          ${pkgs.munge}/bin/mungekey --create --keyfile=${config.services.munge.password}
          chown munge:munge ${config.services.munge.password}
          chmod 0400 ${config.services.munge.password}
        '';
      };

      # slurmdbd's database password, made once on this host and set on MariaDB's `slurm` user
      slurmdbd-storage-pass = {
        description = "Set slurmdbd's database password";
        wantedBy = [ "slurmdbd.service" ];
        before = [ "slurmdbd.service" ];
        after = [ "mysql.service" ];
        requires = [ "mysql.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          pass=/var/lib/slurmdbd/storage-pass
          if [ ! -s "$pass" ]; then
            install -d -m 0700 /var/lib/slurmdbd
            (umask 077; tr -dc A-Za-z0-9 </dev/urandom | head -c 32 >"$pass")
          fi
          ${config.services.mysql.package}/bin/mysql -u root \
            -e "ALTER USER 'slurm'@'localhost' IDENTIFIED BY '$(cat "$pass")';"
        '';
      };

      slurmctld = {
        wants = [ "slurmdbd.service" ];
        after = [ "slurmdbd.service" ];
      };

      # every login account (the owner and the standard users) gets an association, without
      # which AccountingStorageEnforce refuses its jobs
      slurm-accounts = {
        description = "Add the host's users to Slurm accounting";
        wantedBy = [ "multi-user.target" ];
        after = [ "slurmdbd.service" "slurmctld.service" ];
        requires = [ "slurmdbd.service" ];
        environment.SLURM_CONF = slurmConf;
        serviceConfig.Type = "oneshot";
        script = ''
          for _ in $(seq 60); do ${slurm}/bin/sacctmgr -n list cluster >/dev/null 2>&1 && break; sleep 1; done
          ${slurm}/bin/sacctmgr -i add cluster ${host} || true
          ${slurm}/bin/sacctmgr -i add account ${account} Cluster=${host} Description="${host} users" || true
          for user in ${lib.escapeShellArgs members}; do
            ${slurm}/bin/sacctmgr -i add user "$user" Account=${account} Cluster=${host} || true
          done
          # PrivateData hides other users' jobs; the owner still sees and manages them all
          ${slurm}/bin/sacctmgr -i modify user ${username} set AdminLevel=Admin || true
        '';
      };
    };

    dot.help = {
      slurm = {
        title = "Running jobs: the cores, memory${lib.optionalString tt.enable " and the Tenstorrent card"} through Slurm";
        text = ''
          srun -c 8 --mem=16G --pty bash${lib.optionalString tt.enable "              # a shell; add --gres=tt:1 for the card"}
          sbatch job.sh                               # unattended (#SBATCH lines at its top)
          squeue -u $USER / scancel <id> / sinfo      # yours, stop one, how busy it is
          Jobs default to ${cfg.defaultTime} (max ${cfg.maxTime}) and 2 GiB per CPU; logins share ${toString cfg.login.cpus} CPUs and ${toString (cfg.login.memory / 1024)} GiB.
        '';
        file = "nix/nixos/modules/slurm/slurm.md";
      };
      slurm-admin = {
        title = "Slurm: accounts, the queue and the card (admin)";
        profiles = [ "admin" ];
        text = ''
          Every user in profiles.users gets an association in `${account}` at boot (slurm-accounts.service).
          sacctmgr show assoc format=account,user,adminlevel   # who's in
          squeue / scontrol show job <id>                    # everyone's jobs (you're a Slurm admin)
          scontrol update nodename=${host} state=resume      # after a drain
          getfacl /dev/tenstorrent/0                         # who holds the card now (only a job's user)
        '';
      };
    };

    estate.services = [
      { name = "slurmctld"; unit = "slurmctld.service"; notes = "one-node cluster ${host}: partition main (${cfg.defaultTime} default, ${cfg.maxTime} max), fairshare"; }
      { name = "slurmd"; unit = "slurmd.service"; notes = "schedules cores and memory${lib.optionalString tt.enable ", ${toString cfg.cards}x tt:${cfg.cardType} (card ACL granted per job)"}; logins capped at ${toString cfg.login.cpus} CPUs, ${toString cfg.login.memory} MiB"; }
      { name = "slurmdbd"; unit = "slurmdbd.service"; notes = "accounting on local MariaDB; users: ${lib.concatStringsSep ", " members}"; }
    ];
  };
}
