{ ... }: {
  imports = [ ./apiserver.nix ];

  deployment.keys."ca.pem" = {
    keyFile = ../../certs/generated/kubernetes/ca.pem;
    destDir = "/var/lib/secrets/kubernetes";
    user = "kubernetes";
  };
}