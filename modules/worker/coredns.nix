{ pkgs, resourcesByRole, self, ... }:
let
  inherit (import ../../consts.nix) virtualIP;
  inherit (import ../../utils.nix) nodeIP;
in
{
  deployment.keys = {
    "coredns-kube.pem" = {
      keyFile = ../../certs/generated/coredns/coredns-kube.pem;
      destDir = "/var/lib/secrets/coredns";
      user = "coredns";
    };
    "coredns-kube-key.pem" = {
      keyFile = ../../certs/generated/coredns/coredns-kube-key.pem;
      destDir = "/var/lib/secrets/coredns";
      user = "coredns";
    };
    "kube-ca.pem" = {
      keyFile = ../../certs/generated/kubernetes/ca.pem;
      destDir = "/var/lib/secrets/coredns";
      user = "coredns";
    };
  };

  services.coredns = {
    enable = true;
    config = ''
      .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          endpoint https://${virtualIP}
          tls /var/lib/secrets/coredns/coredns-kube.pem /var/lib/secrets/coredns/coredns-kube-key.pem /var/lib/secrets/coredns/kube-ca.pem
          pods verified
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
      }
    '';
  };

  services.kubernetes.kubelet.clusterDns = nodeIP self;

  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  users.groups.coredns = { };
  users.users.coredns = {
    group = "coredns";
    isSystemUser = true;
  };
}
