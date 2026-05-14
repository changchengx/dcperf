# PCIe Function Level Reset (FLR) — Notes

> Source: PCI Express® Base Specification Revision 6.3, primarily §6.6.2,
> with cross-references to §2.3.1.1, §2.3.2, §9.2.2 (SR-IOV), §11.4.9
> (TDISP).

---

## Part 1 — How to understand FLR

### 1.1 One-line mental model

**FLR resets a single PCIe Function back to its initialization state, without
touching the Link or any other Function on the device.** It is the
finest-grained reset PCIe defines: where Conventional / Hot Reset hits a
whole hierarchy domain or device, FLR scopes the blast radius to one
Function.

> Spec §6.6.2 (line 27017): *"The FLR mechanism enables software to quiesce
> and reset Endpoint hardware with Function-level granularity. … FLR applies
> on a per Function basis. Only the targeted Function is affected by the FLR
> operation. The Link state must not be affected by an FLR."*

Implementation of FLR is **optional** but **strongly recommended**. In
practice, most modern Endpoints implement it, and SR-IOV VFs / PFs are
**required** to.

### 1.2 Why FLR exists — three driver-visible use cases

The spec enumerates three motivating scenarios. They map to real-world
driver code well:

| Use case | Real-world example |
|---|---|
| Driver/process crashed and you must stop in-flight DMA | Recovering a hung NIC/storage device when the user-space driver dies |
| Hardware migrated between security domains | Reassigning a VF from one VM/tenant to another — must wipe residual secrets |
| Tearing down and rebuilding the SW stack | `rmmod`/`modprobe` cycle, VFIO unbind/rebind |

Other reset types do not necessarily stop **external** I/O (e.g. a NIC's
link-side traffic) and they are not Function-scoped. FLR fills both gaps.

### 1.3 How FLR is triggered

A configuration write to the **`Initiate Function Level Reset`** bit in the
**Device Control register** (PCIe capability, offset 0x08 in the legacy
view). That single bit is the entire programmer-visible interface — every-
thing else is timing rules.

The targeted Function must:

1. **Return the Completion** for that very config write *before* starting
   the reset. The Completion is the "I'll do it" acknowledgement.
2. **Complete the FLR within 100 ms** of that write.

### 1.4 What gets reset, what survives

This is the part that trips driver writers up the most. FLR is *not*
equivalent to a power-on reset. Three buckets:

**Reset to initialization values** — the default; most Function state.

**Preserved through FLR** (§6.6.2, lines 27036–27068):

- *Sticky-type registers* — `ROS`, `RWS`, `RW1CS` (the `S` suffix means
  sticky; survives even Fundamental Reset).
- *`HwInit` registers* — set once by hardware/firmware at power-on.
- A specific list of named fields: `Max_Payload_Size` in Device Control,
  ASPM Control, RCB, Common Clock Configuration, Hardware Autonomous
  Width/Speed Disable, the various SKP-OS / Lane-Margining / Flit-related
  Extended Capabilities, the entire Virtual Channel and Data Link Feature
  capabilities, etc.
- *CMA-SPDM session state* — security sessions outlive an FLR.

**Must NOT be reset** (lines 27069–27073) — strictly preserved:

- ARI Control register
- L1 PM Substates Extended Capability
- Latency Tolerance Reporting Extended Capability
- Precision Time Measurement Extended Capability

**Critically: the Link survives.** Physical Layer and Data Link Layer state
machines are untouched, and `VC0` stays initialized. This is what makes FLR
cheap — no LTSSM retraining, no link-partner involvement.

### 1.5 Behavior during the reset window

§6.6.2 (lines 27119–27133):

- **Incoming Requests**: may be silently dropped (after returning
  flow-control credits) without logging an error.
- **Incoming Completions**: may be treated as Unexpected Completions or
  silently dropped.
- **Re-config attempts that arrive before Function-specific init is done**:
  must be answered with **Request Retry Status (RRS)** Completions until
  the Function is ready to answer normally. Once it answers a config read
  with non-RRS, it can no longer go back to RRS without another reset.
- **Bus Master Enable, MSI Enable, INTx**: cleared. The Function becomes
  quiescent on the Link. Any pending `Assert_INTx` must be torn down with a
  `Deassert_INTx` *before* the FLR starts (line 27081).

### 1.6 The single biggest pitfall — stale Completions

If software issues an FLR while non-posted Requests are outstanding, the
Completions for those Requests *can still arrive after the FLR*. The
Function lost its tag table during reset, so it cannot tell those old
Completions apart from Completions for new Requests issued post-FLR.
**Result: data corruption.**

The spec gives an explicit safe algorithm (lines 27141–27150):

1. Synchronize with anything else that might touch the Function.
2. **Clear the entire Command register** (`Bus Master Enable`,
   `Memory Space Enable`, `I/O Space Enable`) — stops new Requests from
   being issued.
3. **Poll the `Transactions Pending` bit** in Device Status until clear,
   OR until you are confident Completions can no longer arrive (use the
   pre-FLR Completion-Timeout value — typically tens of ms; if Completion
   Timeouts are disabled, wait at least 100 ms).
4. *Only then* write the `Initiate FLR` bit.

If you skip step 3, you are in stale-Completion territory.

Fast-path: if the device implements **Function Readiness Status (FRS,
§6.22.2)**, software is allowed to start issuing config requests as soon
as it sees the `Configuration-Ready` FRS Message — but per line 27092,
that does *not* tell you outstanding Requests have completed; it only
says config space is ready.

### 1.7 Functional-correctness criteria

Because FLR has to reset state the spec does not even know about
(vendor-specific accelerator state, scratch SRAMs, etc.), the spec falls
back to *behavioral* requirements (lines 27101–27115):

- The Function must not look like an initialized adapter to any **external**
  interface (e.g. a NIC must not respond to network probes that imply
  host-driver presence).
- Any Function-internal storage that could leak secrets to host software
  (caches, internal RAMs, etc.) must be **cleared or randomized**.
- After FLR, normal config-space programming must be sufficient to bring
  the Function back into a useable state for its driver.

### 1.8 SR-IOV interaction (§9.2.2.2 / §9.2.2.3)

- **VF FLR** (line 54912): VFs **must** implement FLR. An FLR to a VF
  resets the VF's Function state but **does not destroy the VF** —
  `VF Enable` in the PF's SR-IOV cap, the VF's BARn values, and the VF
  Resizable BAR capability all survive. This is what lets a hypervisor
  reuse a VF when re-assigning it to a different VM.
- **PF FLR** (line 54918): PFs **must** implement FLR. An FLR to a PF
  *does* reset `VF Enable`, so all child VFs **disappear** as a side
  effect.

### 1.9 TEE-I/O / TDISP interaction (§11.4.9)

- An FLR on a VF/non-IOV Function affects the TDI hosted by that Function;
  an FLR on a PF affects all subordinate VF TDIs (line 59014).
- Affected TDIs transition `CONFIG_LOCKED, RUN → ERROR`, and a
  `STOP_INTERFACE_REQUEST` is required to scrub TVM data/secrets before
  they can move back to `CONFIG_UNLOCKED`.
- FLR on a non-Function-0 Function **does not** tear down active SPDM
  sessions or IDE streams (line 59019). That decoupling is intentional —
  re-establishing security sessions is expensive.

### 1.10 Two anchors to remember

1. **"FLR = SW-issued, single-Function quiesce + state wipe; everything
   Link-side survives."** If a question is about Link state, LTSSM, or
   other Functions, FLR is *not* the answer — that is a Hot / Conventional
   / Fundamental Reset.
2. **"Stop new requests, drain old completions, *then* push the FLR
   button."** This single sequence is what separates a working FLR-using
   driver from a corrupting one.

In Linux, `__pci_reset_function_locked()` / `pci_dev_specific_reset()`
implement exactly the algorithm in §6.6.2 — Command-clear → poll
Transactions Pending → write `Initiate FLR` → wait 100 ms → re-init the
Function.

---

## Part 2 — Vendor ID and Command register values during FLR

### 2.1 Direct answer

**During FLR (before it completes), the Function does not actually return
values for any of its config registers.** It returns **RRS — Request Retry
Status — Completion Status** for every Configuration Request, including
reads of Vendor ID and Command. What the *CPU* sees on the read depends
entirely on the Root Complex (RC) — specifically whether **Configuration
RRS Software Visibility** is enabled.

### 2.2 What the Function does on the wire

§6.6.2 (lines 27128–27133):

> *"While a Function is required to complete the FLR operation within the
> time limit described above, the subsequent Function-specific initialization
> sequence may require additional time. If additional time is required, the
> Function must return a Request Retry Status (RRS) Completion Status when a
> Configuration Request is received after the time limit above. After the
> Function responds to a Configuration Request with a Completion status
> other than RRS, it is not permitted to return RRS in response to a
> Configuration Request until it is reset again."*

Combined with §6.6.2 line 27122 (incoming non-config Requests during FLR
may be silently dropped), the only thing that ever gets a real response
during FLR is a Configuration Request, and that response is RRS.

So at the **wire level** for both Vendor ID and Command register reads:
**`CplD` with Status = RRS, no data payload.**

### 2.3 What the CPU sees — case 1: RRS Software Visibility *disabled* (default)

§2.3.2 (lines 6236–6237):

> *"If Configuration RRS Software Visibility is not enabled, the Root
> Complex must re-issue the Configuration Request as a new Request."*

The RC simply **retries the config read in a hardware loop** until either
it succeeds or the RC gives up.

| Register read | What the CPU sees |
|---|---|
| Vendor ID (offset 0x00) | The CPU **stalls** on the config-read until the Function answers non-RRS, or the RC abandons the loop. If the RC gives up (timer / retry-cap), the read typically completes as if it were a UR → **`0xFFFF`** for Vendor ID, **`0xFFFF…F`** for any wider read (per the IMPLEMENTATION NOTE at lines 6286–6289). |
| Command (offset 0x04) | Same — stall, then `0xFFFF` if the RC gives up. |

This is why, on legacy systems, an FLR can appear to hang config-space
probing until the Function exits the reset.

### 2.4 What the CPU sees — case 2: RRS Software Visibility *enabled*

This is the modern default for OSes that want to be FLR-aware. Enabled
per Root Port via `Configuration RRS Software Visibility Enable` in the
Root Control Register (§7.5.3.12), or per RCRB via the equivalent bit in
the RCRB Control Register (§7.9.7.4).

In this mode the RC does **not** retry — it synthesizes a special
read-data value, but only for one very specific kind of request.

§2.3.2 (lines 6239–6245):

> *"For a Configuration Read Request that includes both bytes of the
> Vendor ID field of a device Function's Configuration Space Header, the
> Root Complex must complete the Request to the host by returning a
> read-data value of 0001h for the Vendor ID field and all 1's for any
> additional bytes included in the request. This read-data value has been
> reserved specifically for this use by the PCI-SIG and does not
> correspond to any assigned Vendor ID. … For a Configuration Write
> Request or for any other Configuration Read Request, the Root Complex
> must re-issue the Configuration Request as a new Request."*

So the answer becomes register-specific:

| Register read | CPU sees during FLR |
|---|---|
| **Vendor ID** alone (`config_read16(0x00)`) | **`0x0001`** — the PCI-SIG-reserved "FLR-in-progress" sentinel. |
| **Vendor ID + Device ID** (`config_read32(0x00)`) | **`0xFFFF_0001`** — Vendor ID = `0x0001`, Device ID synthesized as all 1's. (Little-endian: low half is Vendor ID = `0x0001`.) |
| **Command** (`config_read16(0x04)`) | The synthesis rule above does **not** apply — the request must include both bytes of Vendor ID at offset 0x00. So the RC falls back to retrying. The CPU stalls (and may eventually see `0xFFFF` if the RC gives up). |
| Anything else | Same as Command — RC retries. |

The reason the spec singles out Vendor ID and not, say, Command: lines
5977–5980 say software intending to take advantage of this sentinel
**must** make its first post-reset config access a read that includes
Vendor ID. That gives software a single, well-known place to poll for
"still in FLR" without having to keep the CPU stalled.

### 2.5 Important: `0x0001` is NOT `0xFFFF`

This is the confusion point that trips a lot of people up.

| Value | Meaning |
|---|---|
| **`0xFFFF`** as Vendor ID | "no device responds at this BDF" — Unsupported Request → all-1's synthesis at the RC (lines 6285–6289). |
| **`0x0001`** as Vendor ID | "device exists but is in FLR (or other valid reset condition); please retry later." PCI-SIG-reserved sentinel; no real vendor uses ID `0x0001`. |

A driver doing `if (vid == 0xFFFF) "device gone"; else "ready"` will
**misinterpret** an FLR-in-progress as a working device with vendor
`0x0001`. Robust drivers / the Linux PCI core specifically check for
`0xFFFF_0001` and treat it as "RRS in progress, retry".

The valid reset conditions after which a Function may return RRS are
listed in §6.6 (lines 5845–5848): Cold/Warm/Hot Reset, FLR, and the reset
caused by a `D3hot → D0uninitialized` device-state transition. A
*software-initiated* reset other than FLR (e.g. a vendor-specific reset
bit) is **not** allowed to return RRS (lines 5850–5851).

### 2.6 After FLR completes — what `Command` and `Vendor ID` actually become

The moment the Function returns its first non-RRS Completion:

| Register | Post-FLR value |
|---|---|
| **Vendor ID** (RO, type `HwInit`) | The **device's real Vendor ID** — preserved across FLR (HwInit registers are explicitly listed as "not affected by FLR" in §6.6.2, line 27038). |
| **Command** | **`0x0000`** — cleared by FLR. Specifically: `Bus Master Enable`, `Memory Space Enable`, `I/O Space Enable`, `MSI Enable`, `INTx Disable` all clear. The spec calls this out at line 27077: *"the controls that enable the Function to initiate requests on PCI Express are cleared, including Bus Master Enable, MSI Enable, and the like, effectively causing the Function to become quiescent on the Link."* This is why a driver must re-program `Command` (typically `pci_set_master()` + restore `BusMaster|MMIO|IO`) after every FLR. |

### 2.7 TL;DR

- During FLR the *Function* always returns **RRS** for every config
  request — it has no register values to give yet.
- The CPU-visible value of a read of **Vendor ID** during FLR is either
  **`0x0001`** (with Device ID synthesized as `0xFFFF`) if RRS Software
  Visibility is enabled, or a **stall** (eventually `0xFFFF` on RC
  give-up) if it is not.
- The CPU-visible value of a read of **Command** during FLR is **never**
  the synthesized sentinel — the special handling only applies to reads
  that include the Vendor ID field. Command reads stall and, if anything,
  eventually decay to `0xFFFF` on RC retry exhaustion.
- Once FLR completes: Vendor ID is the device's normal HwInit value;
  Command register is **`0x0000`** (FLR clears all the request-enable
  bits).
