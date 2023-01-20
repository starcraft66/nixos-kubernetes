# Production-grade highly-available Kubernetes on NixOS

Based on https://github.com/justinas/nixos-ha-kubernetes

---

<!-- vim-markdown-toc GFM -->

* [About](#about)
    * [Motivation](#motivation)
    * [Architecture](#architecture)
    * [Goals](#goals)
    * [Future goals](#future-goals)
* [Trying it out](#trying-it-out)
    * [Prerequisites](#prerequisites)
    * [Running the development cluster](#running)
    * [Verifying](#verifying)
    * [Modifying](#modifying)
    * [Destroying](#destroying)
    * [Tips and tricks](#tips-and-tricks)
* [Contributing](#contributing)
* [Acknowledgements](#acknowledgements)

<!-- vim-markdown-toc -->

## About

I hope for this project to become a resource to build robust production-grade kubernetes clusters on bare metal servers and/or virtual machines running NixOS.
A sample [Terraform](https://www.terraform.io/) deployment for running such a cluster for development and testing is provided. At the moment, it only supports deployment on linux hosts running libvirt.
Everything is deployed quickly in parallel using [Colmena](https://github.com/zhaofengli/colmena).

### Motivation

I started my kubernetes journey when I was still learning the basics of Nix. I saw that there was a NixOS module in nixpkgs for running Kubernetes, however, it looked very basic and left essential tasks to the reader like certificate management. There is an "easy-certs" bootstrap mode but it is noted that it is insecure and should not be used for production clusters. High availability support is also limited using this module.

I ended up going down the path of deploying my cluster on Ubuntu servers using the kubespray ansible playbook. I already wasn't fond of ansible back then and am even less fond of it after managing a kubernetes cluster using it. It is dog slow and bloats your system with accumulated state. During the couple of years I've been running a cluster for, I've always been on the lookout for better kubernetes deployment tools and made gripes against pretty much every kubernetes installer out there. Some of them only support deploying in the cloud and almost all of them require you to separately install and manage a linux distribution underneath them so that they can do their work.

Using NixOS, I hope to alleviate the pain points laid out above by deploying a stateless operating system pre-configured to run a highly available Kubernetes cluster on bare metal. This methodology will allow for easy up and downgrades as well as manual cluster scaling.

Because the nixpkgs kubernetes module is unsuitable for running a production-grade cluster, I hope to build my own modules and provide my own packages to offer the best kubernetes experience on NixOS independently of nixpkgs.

### Architecture

External etcd topology,
[as described by Kubernetes docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/#external-etcd-topology),
is implemented.
A cluster consists of:
* 3+ `etcd` nodes
* 3+ `controlplane` nodes, running
  `kube-apiserver`, `kube-controller-manager`, and `kube-scheduler`.
* 1+ `worker` nodes, running `kubelet`, `kube-proxy`,
  `coredns`, and a CNI network (currently `flannel`).
* 1+ `loadbalancer` nodes, running `keepalived` and `haproxy`,
  which proxies to the Kubernetes API.

The demo cluster contained in this repo deploys a cluster containing:
* 3 `etcd` nodes
* 3 `controlplane` nodes
* 2 `worker` nodes
* 2 `loadbalancer` nodes

### Goals
* All infrastructure declaratively managed using Nix and deployed with Colmena. (The development cluster is managed by Terraform.)
* Infrastructure-level services run directly on NixOS / systemd when it makes sense to do so.
  The Cilium CNI will be installed using their officially-supported installer once the cluster is running.
* Functionality, the cluster should have 100% parity with clusters deployed by `kubeadm`.
* High-availability.
  A failure of a single service (of any kind) or a single machine (of any role)
  shall not leave the cluster in a non-functional state.

### Future goals
* Self-contained.
  This project won't need to rely on nixpkgs for upstream kubernetes modules or kubernetes packages.
  All of the packages for kubernetes components will be provided by the flake and for multiple given versions of kubernetes, not just the one that happens to be available in nixpkgs.
* Cluster TLS PKI bootstrapping and management using [HashiCorp Vault](https://github.com/hashicorp/vault) and [consul-template](https://github.com/hashicorp/consul-template).
* Use of cilium's BGP control plane.
  Will enable high-availability of all networking endpoints using pure layer-3 networking.
  Additional router VMs will be added to the development cluster for the cluster nodes to peer with.

## Trying it out

### Prerequisites

* Nix (only tested on NixOS, might work on other Linux distros).
* Libvirtd running. For NixOS, put this in your config:
  ```nix
  {
    virtualisation.libvirtd.enable = true;
    users.users."yourname".extraGroups = [ "libvirtd" ];
  }
  ```
* At least 6 GB of available RAM.
* At least 15 GB of available disk space.
* `10.240.0.0/24` IPv4 subnet available (as in, not used for your home network or similar).
  This is used by the "physical" network of the VMs.

### Running the development cluster

```console
$ nix-shell
$ make-boot-image # Build the base NixOS image to boot VMs from
$ ter init        # Initialize terraform modules
$ ter apply       # Create the virtual machines
$ make-certs      # Generate TLS certificates for Kubernetes, etcd, and other daemons.
$ colmena apply   # Deploy to your cluster
$ cilium install  # Install cilium into the cluster
$ cilium hubble enable --ui # Enable the cilium hubble observatory
```

Most of the steps can take several minutes each when running for the first time.

### Verifying

```console
$ ./check.sh                # Prints out diagnostic information about the cluster and tries to run a simple pod.
$ k run --image nginx nginx # Run a simple pod. `k` is an alias of `kubectl` that uses the generated admin credentials.
```

### Modifying

The number of servers of each role can be changed by editing `terraform.tfvars`
and issuing the following commands afterwards:

```console
$ ter apply     # Spin up or spin down machines
$ make-certs    # Regenerate the certs, as they are tied to machine IPs/hostnames
$ colmena apply # Redeploy
```

### Destroying

```console
$ ter destroy   # Destroy the virtual machines
$ rm boot/image # Destroy the base image
```

### Tips and tricks

* After creating and destroying the cluster many times, your `.ssh/known_hosts`
  will get polluted with many entries with the virtual machine IPs.
  Due to this, you are likely to run into a "host key mismatch" errors while deploying.
  I use `:g/^10.240.0./d` in Vim to clean it up.
  You can probably do the same with `sed` or similar software of your choice.

## Contributing

Contributions are welcome, although I might reject any that conflict with the project goals.
See [TODOs](https://github.com/justinas/nixos-ha-kubernetes/search?q=TODO) in the repo
for some rough edges you could work on.

Make sure the `ci-lint` script succeeds.
Make sure the `check.sh` script succeeds after a deploying a fresh cluster.

## Acknowledgements

Both [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
and [Kubernetes The Hard Way on Bare Metal](https://github.com/Praqma/LearnKubernetes/blob/master/kamran/Kubernetes-The-Hard-Way-on-BareMetal.md)
helped me immensely in this project.
