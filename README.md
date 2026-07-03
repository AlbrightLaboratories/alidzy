<!-- toc-backlink -->
> 📚 **Master TOC:** [Org-wide repo index](https://github.com/AlbrightLaboratories/daxxon-ai-gpu-01/issues/17) — auto-updated every 15 min from this repo's commit stream. No manual entry needed; just write commit subjects that read well as one-line bullets.

# Alidzy

> Renamed from **compute-monster** on 2026-07-03 (repo + hostname `alidzy`). Old URLs redirect.

**Purpose:** consolidate and retire three aging cluster nodes — **worker-07**, **worker-06**, and **worker-04** — into a single, higher-density "compute monster" workstation. The new box absorbs the workloads currently spread across those three workers so they can be powered down, stripped, and removed from the cluster.

> **Platform note:** originally scoped as an AM5/DDR5 ASUS B650E build. That board wouldn't POST after transplant, so it was **downgraded to AM4/DDR4** and rebuilt around a locally-bought **MSI B550-A PRO + Ryzen 7 5800X + RTX 3060 Ti**. The box **POSTs and runs** today; remaining work is software (Linux + cluster join).

## Why retire these nodes

| Node | Status | Disposition |
|------|--------|-------------|
| worker-07 | Retiring | Drain → cordon → decommission; reusable parts harvested |
| worker-06 | Retiring | Drain → cordon → decommission; reusable parts harvested |
| worker-04 | Retiring | Drain → cordon → decommission; reusable parts harvested |

Three older worker nodes are collapsed into one box. The Ryzen 7 5800X (8C/16T, Zen 3) plus **64 GB of DDR4** delivers more usable compute than the three legacy Mac Pro VMs combined (~11 vCPU / ~49 GiB), while cutting rack space, cabling, cooling load, and machines to patch — and it adds a usable **RTX 3060 Ti** GPU.

## Build — bill of materials (as built, POSTing)

Manufacturer-verified identities (full detail + sources in [`docs/`](docs/README.md)):

| Component | Part | Notes |
|-----------|------|-------|
| Motherboard | MSI **B550-A PRO** (AMD B550, **AM4**, ATX) | 4×DDR4, 2×M.2, 6×SATA, **1 GbE**, no WiFi |
| CPU | AMD **Ryzen 7 5800X** — 3.8/4.7 GHz, 8C/16T, 105 W | **no iGPU → discrete GPU required** |
| CPU cooler | **AIO liquid** (radiator + pump) | radiator mounted **above** the pump |
| Memory | **64 GB DDR4** (UDIMM) | beats the ~49 GiB being retired; A-XMP → 3600 1:1 |
| GPU | NVIDIA **RTX 3060 Ti** (8 GB, ~200 W) | the box's **only video source** + light ML/inference |
| Boot/data | **1 TB NVMe** in M2_1 (PCIe 4.0 x4) | |
| Bulk | **2 TB Seagate** HDD (SATA) | mount as `/data` |
| PSU | installed — **confirm model/wattage** | needs ~350–400 W load headroom + 3060 Ti PCIe power |
| Case | KEDIERS **K4 (MAX)** ATX dual-chamber | 420 mm rad, 175 mm cooler, full glass |
| Fans / RGB | Lian Li **UNI FAN SL-Infinity 120** + **SL-INF 140 Reverse** + **UNI controller** | [placement + lighting](docs/08-case-and-fan-placement.md) |

> **The build is complete** — it POSTs with a GPU, boot NVMe, bulk HDD, 64 GB RAM, and AIO cooling. What's left is **software**: wipe Windows → install Linux → `kubeadm join`. See [`docs/06`](docs/06-assembly-and-bios-setup.md). One open item: **verify the installed PSU** is a quality unit with the right PCIe connectors for the 3060 Ti ([`docs/01`](docs/01-hardware-bom.md)).

## Hardware docs

Manufacturer-sourced reference (MSI / AMD, official docs first) lives in [`docs/`](docs/README.md): per-component specs, the memory-sizing decision, and the assembly + BIOS + Linux-install procedure.

## Retirement procedure

Run for each of worker-07, worker-06, worker-04, one node at a time:

1. **Cordon** the node so the scheduler stops placing new work on it.
   ```sh
   kubectl cordon <node>
   ```
2. **Drain** running pods, evicting gracefully.
   ```sh
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
   ```
3. **Verify** nothing is left scheduled and the cluster is healthy (no pending pods, no warnings/events that trace back to the drain).
   ```sh
   kubectl get pods -A -o wide | grep <node>   # should return nothing
   kubectl get nodes
   ```
4. **Remove** the node from the cluster.
   ```sh
   kubectl delete node <node>
   ```
5. **Power down**, label, and pull the machine. Harvest reusable parts.

## Migration checklist

- [ ] Confirm replacement capacity (the new build) is online and joined to the cluster before draining anything.
- [ ] worker-07 — cordon → drain → delete → power off
- [ ] worker-06 — cordon → drain → delete → power off
- [ ] worker-04 — cordon → drain → delete → power off
- [ ] Confirm no orphaned PersistentVolumes / storage tied to the retired nodes.
- [ ] Remove retired nodes from any monitoring, DNS, and inventory.
- [ ] Update the cluster topology docs to reflect the new node count.
