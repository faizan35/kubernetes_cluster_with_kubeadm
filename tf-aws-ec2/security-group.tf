resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "kubeadm CKA lab cluster"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

# ---------------------------------------------------------------------------
# Node-to-node: allow everything inside the security group.
#
# THE most important rule here. Without it the cluster comes up looking
# perfectly healthy -- kubeadm init succeeds, `kubectl get nodes` shows Ready --
# and then fails in confusing ways much later:
#
#   port 10250       kubelet API. Without it `kubectl logs` and `kubectl exec`
#                    HANG for any pod on a worker, and metrics-server never works.
#   port 179 / 4789  Calico BGP and VXLAN. Cross-node pod networking dies silently.
#   port 2379-2380   etcd peer and client.
#   port 10257/10259 controller-manager and scheduler.
#
# One self-referencing rule covers all of them plus anything a different CNI needs.
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "internal_all" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "All traffic between cluster nodes"
}

# ---------------------------------------------------------------------------
# From your machine
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH"
}

resource "aws_vpc_security_group_ingress_rule" "kube_api" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  description       = "kube-apiserver"
}

# Week 3 Day 15 requires reaching a NodePort service from outside the cluster.
resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  description       = "NodePort service range"
}

# Week 3 Day 17, in case you run an ingress controller with hostNetwork.
resource "aws_vpc_security_group_ingress_rule" "http_https" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 443
  description       = "HTTP/HTTPS for Ingress and Gateway API testing"
}

# ---------------------------------------------------------------------------
# Egress
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}
