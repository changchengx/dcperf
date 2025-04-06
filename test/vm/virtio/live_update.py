#!/usr/bin/env python3

import argparse
import json
import subprocess

spdk_script = 'spdk_rpc.py'
snap_script = 'snap_rpc.py'

#################################     RPCs     #################################
def send_recv_rpc(sock, script, method, params=None):
    """
    Sends RPC to a process using the CRI and returns the response.

    Args:
        sock (str): The sock name of the process where the RPC should be executed.
        script (str): The script that should be executed, spdk_rpc.py or snap_rpc.py.
        method (str): The name of the RPC method to be invoked.
        params (list, optional): A list of additional parameters to be passed to the RPC method. Defaults to None.

    Returns:
        dict: The response received from the RPC method, parsed as a JSON object.
    """
    cmd = [script, "-s", sock, method]
    if params:
        cmd = cmd + params
    try:
        print(' '.join(cmd))
        result = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        response = json.loads(result.stdout)
        return response
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {cmd}")
        print(f"Command returned non-zero exit code {e.returncode}")
        print(f"Standard Error:\n{e.stderr}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON: {e}")
        raise

def send_rpc(sock, script, method, params=None):
    """
    Sends RPC to a process using the CRI.

    Args:
        sock (str): The sock name of the process where the RPC should be executed.
        script (str): The script that should be executed, spdk_rpc.py or snap_rpc.py.
        method (str): The name of the RPC method to be invoked.
        params (list, optional): A list of additional parameters to be passed to the RPC method. Defaults to None.
    """
    cmd = [script, "-s", sock, method]
    if params:
        cmd = cmd + params
    try:
        print(f"send rpc command : {cmd}")
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {cmd}")
        print(f"Command returned non-zero exit code {e.returncode}")
        print(f"Standard Error:\n{e.stderr}")
        raise

def send_suspend_restore(src_sock, dst_sock, suspend_cmd, create_cmd):
    """
    Sends suspend and restore commands to source and destination containers.

    Args:
        src_sock (str): The ID of the source process.
        dst_sock (str): The ID of the destination process.
        suspend_cmd (str): The command to suspend resources in the source container.
        create_cmd (str): The command to restore or create resources in the destination container.
    """
    send_rpc(src_sock, snap_script, suspend_cmd)
    send_rpc(dst_sock, snap_script, create_cmd)

##########################     LiveUpgradeManager     ##########################
class LiveUpgradeManager:
    def __init__(self, src_sock, dst_sock):
        """
        Initializes an instance of the class with the provided source and destination sock.

        Args:
            src_sock (str): The sock name of the source process.
            dst_sock (str): The sock name of the destination process.
        """
        self.src_sock = src_sock
        self.dst_sock = dst_sock
        self.bdev_dict, self.bdev_nvmf_dict = self.get_bdev_info()
        self.nvme_functions, self.vblk_functions = self.get_emulation_functions()
        self.vblk_ctrl_dict, self.nvme_ctrl_dict = self.get_controller_info()
        self.nvme_subsys_dict, self.nvme_subsys_hist = self.get_subsystem_info()
        self.fill_bdev_hist()

    ###############################     GetSnapState     ###########################
    def get_bdev_info(self):
        """
        Retrieves block device information and populates dictionaries with the relevant details.

        Returns:
            tuple: A tuple containing 2 dictionaries:
                - bdev_dict (dict): A dictionary of all block devices.
                - bdev_nvmf_dict (dict): A dictionary of NVMe block devices.

        Note:
            - The method invokes an RPC to retrieve block device information.
            - The dictionaries are populated based on the product_name of the block devices.
        """
        print("Retrieving block device information...")
        bdev_get_bdevs = send_recv_rpc(self.src_sock, spdk_script, 'bdev_get_bdevs')
        bdev_get_controllers = send_recv_rpc(self.src_sock, spdk_script, 'bdev_nvme_get_controllers')
        bdev_nvmf_dict = {ctrl['name']: {"created": 0, "used": 0} for ctrl in bdev_get_controllers}

        bdev_dict = dict()
        for bdev in bdev_get_bdevs:
            if bdev['product_name'] ==  "NVMe disk":
                for bdev_ctrl in bdev_get_controllers:
                    if bdev['driver_specific']['nvme'][0]['trid'].items() == bdev_ctrl['ctrlrs'][0]['trid'].items():
                        bdev_dict.update({bdev['name']: {"info": bdev, "base": bdev_ctrl['name'],"created": 0, "used": 0}})
                        bdev_nvmf_dict[bdev_ctrl['name']]['used'] += 1
            else:
                bdev_dict.update({bdev['name']: {"info": bdev, "created": 0, "used": 0}})
        print(f"    Found {len(bdev_dict)} block devices.")
        return bdev_dict, bdev_nvmf_dict

    def get_emulation_functions(self):
        """
        Retrieves emulation function information and separates them into NVME and VBLK functions.

        Returns:
            tuple: A tuple containing two lists:
                - nvme_functions (list): A list of NVME physical emulation functions.
                - vblk_functions (list): A list of VBLK physical emulation functions.

        Note:
            - The method invokes an RPC to retrieve the emulation function list.
            - The lists are populated based on the 'emulation_type' field.
        """
        print("Retrieving emulation function information...")
        emulation_function_list = send_recv_rpc(self.src_sock, snap_script, 'emulation_function_list')
        nvme_functions = [func for func in emulation_function_list if func['emulation_type'] == "NVME"]
        vblk_functions = [func for func in emulation_function_list if func['emulation_type'] == "VBLK"]
        print(f"    Found {len(nvme_functions)} NVME physical emulation functions and {len(vblk_functions)} VBLK physical emulation functions.")
        return nvme_functions, vblk_functions

    def get_controller_info(self):
        """
        Retrieves controller information and populates dictionaries with the relevant details.

        Returns:
            tuple: A tuple containing two dictionaries:
                - vblk_ctrl_dict (dict): A dictionary of VBLK controllers.
                - nvme_ctrl_dict (dict): A dictionary of NVME controllers.

        Note:
            - The method invokes RPCs to retrieve the VBLK and NVME controller lists.
            - The dictionaries are populated based on the 'ctrl_id' field.
        """
        print("Retrieving controller information...")
        vblk_ctrl_list = send_recv_rpc(self.src_sock, snap_script, 'virtio_blk_controller_list')
        nvme_ctrl_list = send_recv_rpc(self.src_sock, snap_script, 'nvme_controller_list')
        vblk_ctrl_dict = {ctrl['ctrl_id']: ctrl for ctrl in vblk_ctrl_list}
        nvme_ctrl_dict = {ctrl['ctrl_id']: ctrl for ctrl in nvme_ctrl_list}
        print(f"    Found {len(nvme_ctrl_dict)} NVME controllers.")
        print(f"    Found {len(vblk_ctrl_dict)} VBLK controllers.")
        return vblk_ctrl_dict, nvme_ctrl_dict

    def get_subsystem_info(self):
        """
        Retrieves subsystem information and populates dictionaries with the relevant details.

        Returns:
            tuple: A tuple containing two dictionaries:
                - nvme_subsys_dict (dict): A dictionary of NVME subsystems.
                - nvme_subsys_hist (dict): A dictionary to track the history of NVME subsystems.

        Note:
            - The method invokes an RPC to retrieve the NVME subsystem list.
            - The dictionaries are populated based on the 'nqn' field.

        Example:
            nvme_subsys_dict, nvme_subsys_hist = instance.get_subsystem_info()
        """
        print("Retrieving subsystem information...")
        nvme_subsys_list = send_recv_rpc(self.src_sock, snap_script, 'nvme_subsystem_list')
        nvme_subsys_dict = {subsys['nqn']: subsys for subsys in nvme_subsys_list}
        nvme_subsys_hist = {subsys['nqn']: 0 for subsys in nvme_subsys_list}
        print(f"    Found {len(nvme_subsys_dict)} NVME subsystems.")
        return nvme_subsys_dict, nvme_subsys_hist

    def fill_bdev_hist(self):
        nvme_nses_list = send_recv_rpc(self.src_sock, snap_script, 'nvme_namespace_list')
        for bdev in self.bdev_dict:
            for ns in nvme_nses_list:
                if ns['bdev'] == bdev:
                    self.bdev_dict[bdev]['used'] += 1
            for vblk_ctrl in self.vblk_ctrl_dict:
                if self.vblk_ctrl_dict[vblk_ctrl]['bdev'] == bdev:
                    self.bdev_dict[bdev]['used'] += 1

    ###############################     BDEV     ###############################
    def create_bdev(self, bdev):
        """
        Creates a block device (bdev) based on the provided information.

        Args:
            bdev (dict): A dictionary containing the details of the block device.
                - 'name' (str): The name of the block device.
                - 'product_name' (str): The product name of the block device.
                - 'block_size' (int): The block size of the block device.
                - 'num_blocks' (int): The number of blocks of the block device.
                - 'uuid' (str): The UUID of the block device (optional).

        Note:
            - The method supports 3 types of block devices: 'NVMe disk', 'Null disk', and 'Malloc disk'.
            - Depending on the type of block device, different RPC methods are invoked.
        """
        if self.bdev_dict[bdev]['created'] == 1: return

        bdev_info = self.bdev_dict[bdev]['info']
        bdev_name = bdev_info['name']

        if bdev_info['product_name'] ==  "NVMe disk":
            base_bdev = self.bdev_dict[bdev]['base']
            if self.bdev_nvmf_dict[base_bdev] != 'none' and self.bdev_nvmf_dict[base_bdev]['created'] == 1:
                self.bdev_dict[bdev]['created'] = 1
                return
            bdev_nvme = bdev_info['driver_specific']['nvme'][0]['trid']
            bdev_nvme_param = {
                'name': base_bdev,
                'trtype': bdev_nvme['trtype'],
                'adrfam': bdev_nvme['adrfam'],
                'traddr': bdev_nvme['traddr'],
                'trsvcid': bdev_nvme['trsvcid'],
                'subnqn': bdev_nvme['subnqn'],
            }

            params = []
            for key, value in bdev_nvme_param.items():
                params = params + ['--' + key, value]

            send_rpc(self.dst_sock, spdk_script, 'bdev_nvme_attach_controller', params)
            self.bdev_nvmf_dict[base_bdev]['created'] = 1

        elif bdev_info['product_name'] ==  "Null disk" or bdev_info['product_name'] ==  "Malloc disk":
            block_size = bdev_info['block_size']
            num_blocks = bdev_info['num_blocks']
            total_size = int((block_size * num_blocks) / (1024 ** 2))

            if bdev_info['product_name'] ==  "Null disk":
                params = [
                    bdev_info['name'],
                    str(total_size),
                    str(block_size),
                    '--uuid', bdev_info['uuid'],
                ]
                send_rpc(self.dst_sock, spdk_script, 'bdev_null_create', params)

            elif bdev_info['product_name'] ==  "Malloc disk":
                params = [
                    str(total_size),
                    str(block_size),
                    '-b' + bdev_info['name'],
                    '--uuid', bdev_info['uuid'],
                ]
                send_rpc(self.dst_sock, spdk_script, 'bdev_malloc_create', params)

        self.bdev_dict[bdev]['created'] = 1

    def destroy_bdev(self, bdev):
        """
        Destroys a block device (bdev) based on the provided information.

        Args:
            bdev (dict): A dictionary containing the details of the block device.
                - 'name' (str): The name of the block device.
                - 'product_name' (str): The product name of the block device.

        Note:
            - The method supports three types of block devices: 'NVMe disk', 'Null disk', and 'Malloc disk'.
            - Depending on the type of block device, different RPC methods are invoked.
        """
        self.bdev_dict[bdev]['used'] -= 1
        if self.bdev_dict[bdev]['used'] != 0: return

        bdev_info = self.bdev_dict[bdev]['info']

        if bdev_info['product_name'] ==  "NVMe disk":
            base_bdev = self.bdev_dict[bdev]['base']
            self.bdev_nvmf_dict[base_bdev]['used'] -= 1
            if self.bdev_nvmf_dict[base_bdev]['used'] != 0: return
            send_rpc(self.src_sock, spdk_script, 'bdev_nvme_detach_controller', [base_bdev])

        elif  bdev_info['product_name'] ==  "Null disk":
            send_rpc(self.src_sock, spdk_script, 'bdev_null_delete', [bdev_info['name']])

        elif  bdev_info['product_name'] ==  "Malloc disk":
            send_rpc(self.src_sock, spdk_script, 'bdev_malloc_delete', [bdev_info['name']])

    ################################     VBLK     ##############################
    def cleanup_restore_vblk_controller(self, vblk_func):
        """
        Cleans up and restores a vblk controller.

        Args:
        vblk_func (dict): The vblk function to cleanup and restore.
        """
        ctrl_id = vblk_func['ctrl_id']
        ctrl = self.vblk_ctrl_dict[ctrl_id]

        createParams = {
            'vhca_id': str(ctrl['vhca_id']),
            'ctrl': ctrl_id,
            'num_queues': str(ctrl['num_queues']),
            'queue_size': str(ctrl['queue_size']),
            'seg_max': str(ctrl['seg_max']),
            'size_max': str(ctrl['size_max']),
            'vblk_id': str(ctrl['vblk_id']),
        }

        createFlags = {
            'force_in_order': ctrl['force_in_order'],
            'admin_q': ctrl['admin_q'],
            'dbg_local_optimized': ctrl['dbg_local_optimized'],
            'indirect_desc': ctrl['indirect_desc'],
            'read_only': ctrl['read_only'],
        }

        if ctrl['bdev'] != 'none': createParams['bdev'] = ctrl['bdev']
        params = []
        for key, value in createParams.items(): params += ['--' + key, value]

        for key, value in createFlags.items():
            if (value):
                params += ['--' + key]

        params += ['--suspended', '--live_update_listener']

        suspend_cmd = 'virtio_blk_controller_suspend --ctrl ' + ctrl_id + ' -t 20 -lu' + ' ; '
        create_cmd = 'virtio_blk_controller_create ' + ' '.join(params) + ' ; '

        send_suspend_restore(self.src_sock, self.dst_sock, suspend_cmd, create_cmd)

    def suspend_vblk_ctrl(self, vblk_func, params=None):
        """
        Suspend the vblk controller.

        Args:
        vblk_func (dict): The vblk function to suspend.
        """
        suspend_vblk_ctrl_params = {
            'ctrl': vblk_func['ctrl_id'],
        }

        suspend_vblk_ctrl_params_list = []
        for key, value in suspend_vblk_ctrl_params.items():
            suspend_vblk_ctrl_params_list += ['--' + key, value]

        if params:
            suspend_vblk_ctrl_params_list.append('--' + params)

        send_rpc(self.src_sock, snap_script, 'virtio_blk_controller_suspend', suspend_vblk_ctrl_params_list)

    def destroy_vblk_ctrl(self, vblk_func, params=None):
        """
        Destroy the vblk controller.

        Args:
        vblk_func (dict): The vblk function to destroy.
        """
        destroy_vblk_ctrl_params = {
            'ctrl': vblk_func['ctrl_id'],
        }

        destroy_vblk_ctrl_params_list = []
        for key, value in destroy_vblk_ctrl_params.items():
            destroy_vblk_ctrl_params_list += ['--' + key, value]

        if params:
            destroy_vblk_ctrl_params_list.append('--' + params)

        bdev = self.vblk_ctrl_dict[vblk_func['ctrl_id']]['bdev']

        send_rpc(self.src_sock, snap_script, 'virtio_blk_controller_destroy', destroy_vblk_ctrl_params_list)

        # Destroy the bdev after destroying the controller to avoid capacity
        # changing to 0 at the source controller, which would notify the host.
        if bdev != 'none':
            self.destroy_bdev(bdev)

    def live_update_vblk_func(self, vblk_func):
        """
        Performs a live update on a vblk block function.

        Args:
            vblk_func (dict): The vblk function to perform the live update on.
        """
        # check if the function not in use.
        if 'ctrl_id' not in vblk_func: return

        if 'vf_index' not in vblk_func:
            print(f"* Moving Virtio Blk Emulation function; pf_index: {vblk_func['pf_index']}, Started...*")
        else :
            print(f"* Moving Virtio Blk Emulation function; pf_index: {vblk_func['pf_index']} - vf_index: {vblk_func['vf_index']}, Started...*")

        bdev = self.vblk_ctrl_dict[vblk_func['ctrl_id']]['bdev']
        # Check if the controller is dummy.
        if bdev != 'none': self.create_bdev(bdev)

        self.suspend_vblk_ctrl(vblk_func, 'events_only')

        self.cleanup_restore_vblk_controller(vblk_func)

        # Don't destroy the PF before detroying all its VFs
        if 'vf_index' in vblk_func:
            # Use force flag to destroy the VF when SR-IOV is enabled
            self.destroy_vblk_ctrl(vblk_func, 'force')

        if 'vf_index' not in vblk_func:
            print(f"* Moving Virtio Blk Emulation function; pf_index: {vblk_func['pf_index']}, Done.*")
        else :
            print(f"* Moving Virtio Blk function; pf_index: {vblk_func['pf_index']} - vf_index: {vblk_func['vf_index']}, Done.*")

    ###############################     NVMe     ###############################
    # Restore NVMe Subsystems
    def create_nvme_subsys(self, subsys):
        create_subsys_params = {
            's' : subsys['nqn'],
            'mn'  : subsys['mn'],
            'sn'  : subsys['sn'],
            'mnan': subsys['mnan'],
            'nn'  : subsys['nn'],
        }

        create_subsys_params_list = []
        for key, value in create_subsys_params.items():
            create_subsys_params_list = create_subsys_params_list + ['-' + key, str(value)]

        send_rpc(self.dst_sock, snap_script, 'nvme_subsystem_create', create_subsys_params_list)

    def check_nvme_subsys(self, subsys):
        nvme_subsys_list = send_recv_rpc(self.dst_sock, snap_script, 'nvme_subsystem_list')
        nvme_subsys_dict = {subsys['nqn']: subsys for subsys in nvme_subsys_list}
        if subsys['nqn'] in nvme_subsys_dict:
            return True
        return False

    # Restore NVMe Namespace
    def create_nvme_namespace(self, ctrl, ns):
        create_ns_params = {
            'nqn'       : ctrl['nqn'],
            'nsid'      : str(ns['nsid']),
            'bdev_name' : ns['bdev'],
            'uuid'      : ns['uuid'],
        }

        create_ns_params_list = []
        for key, value in create_ns_params.items():
            create_ns_params_list = create_ns_params_list + ['--' + key, value]

        send_rpc(self.dst_sock, snap_script, 'nvme_namespace_create', create_ns_params_list)

    def check_nvme_namespace(self, ctrl, ns):
        nvme_nses_list = send_recv_rpc(self.dst_sock, snap_script, 'nvme_namespace_list')
        for dst_ns in nvme_nses_list:
            if dst_ns['uuid'] == ns['uuid']:
                return True
        return False

    # Suspend NVMe controller
    def suspend_nvme_ctrl(self, ctrl, flag=None, timeout=None):
        suspend_nvme_ctrl_params = {
            'ctrl' : ctrl['ctrl_id'],
        }

        suspend_nvme_ctrl_params_list = []
        for key, value in suspend_nvme_ctrl_params.items():
            suspend_nvme_ctrl_params_list += ['--' + key, value]

        if flag:
            suspend_nvme_ctrl_params_list.append('--' + flag)

        if timeout:
            suspend_nvme_ctrl_params_list +=  ['--timeout_ms', timeout]

        send_rpc(self.src_sock, snap_script, 'nvme_controller_suspend', suspend_nvme_ctrl_params_list)

    # Restore NVMe controller
    def create_passive_nvme_controller(self, ctrl):
        create_ctrl_params = {
            'vhca_id'    : str(ctrl['vhca_id']),
            'ctrl'       : ctrl['ctrl_id'],
            'nqn'        : ctrl['nqn'],
            'mdts'       : str(ctrl['mdts']),
            'num_queues' : str(ctrl['num_queues']),
        }

        create_ctrl_params_list = []
        for key, value in create_ctrl_params.items():
            create_ctrl_params_list = create_ctrl_params_list + ['--' + key, value]

        create_ctrl_params_list = create_ctrl_params_list + ['--suspended', '--live_update_listener']

        send_rpc(self.dst_sock, snap_script, 'nvme_controller_create', create_ctrl_params_list)

        for ns in ctrl['namespaces']:
            attach_ns_params = {
                'ctrl': ctrl['ctrl_id'],
                'nsid': str(ns['nsid']),
            }

            attach_ns_params_list = []
            for key, value in attach_ns_params.items():
                attach_ns_params_list = attach_ns_params_list + ['--' + key, value]
            send_rpc(self.dst_sock, snap_script, 'nvme_controller_attach_ns', attach_ns_params_list)

    # Detach NVMe namespace
    def detach_nvme_ns(self, ctrl_id, nsid):
        detach_nvme_ns_params = {
            'ctrl' : ctrl_id,
            'nsid' : nsid,
        }

        detach_nvme_ns_params_list = []
        for key, value in detach_nvme_ns_params.items():
            detach_nvme_ns_params_list += ['--' + key, value]

        send_rpc(self.src_sock, snap_script, 'nvme_controller_detach_ns', detach_nvme_ns_params_list)

    # Cleanup NVMe controller
    def cleanup_nvme_controller(self, ctrl_id):
        ctrl = self.nvme_ctrl_dict[ctrl_id]

        for ns in ctrl['namespaces']:
            self.detach_nvme_ns(ctrl_id, str(ns['nsid']))
            self.destroy_bdev(ns['bdev'])

        destroy_ctrl_params = {
            'ctrl' : ctrl_id,
        }

        destroy_ctrl_params_list = []
        for key, value in destroy_ctrl_params.items():
            destroy_ctrl_params_list = destroy_ctrl_params_list + ['--' + key, value]

        send_rpc(self.src_sock, snap_script, 'nvme_controller_destroy', destroy_ctrl_params_list)

    def live_update_nvme_func(self, nvme_func):
        # check if the function not in use.
        if 'ctrl_id' not in nvme_func: return

        if 'vf_index' not in nvme_func:
            print(f"* Moving NVMe Emulation function; pf_index: {nvme_func['pf_index']}, Started...*")
        else :
            print(f"* Moving NVMe Emulation function; pf_index: {nvme_func['pf_index']} - vf_index: {nvme_func['vf_index']}, Started...*")

        ctrl_id = nvme_func['ctrl_id']
        ctrl = self.nvme_ctrl_dict[ctrl_id]

        # Creates a subsystem if does not exist.
        if self.nvme_subsys_hist[ctrl['nqn']] == 0 :
            subsys = self.nvme_subsys_dict[ctrl['nqn']]
            if self.check_nvme_subsys(subsys) == False :
                self.create_nvme_subsys(subsys)
            self.nvme_subsys_hist[ctrl['nqn']] = 1

        # Creates a namespace if does not exist.
        for ns in ctrl['namespaces']:
            self.create_bdev(ns['bdev'])
            if self.check_nvme_namespace(ctrl, ns) == False :
                self.create_nvme_namespace(ctrl, ns)

        self.suspend_nvme_ctrl(ctrl, 'admin_only')

        self.create_passive_nvme_controller(ctrl)

        self.suspend_nvme_ctrl(ctrl, 'live_update_notifier', '20')

        # Don't destroy the PF before detroying all its VFs
        if 'vf_index' in nvme_func:
            self.cleanup_nvme_controller(ctrl_id)

        if 'vf_index' not in nvme_func:
            print(f"* Moving NVMe Emulation function; pf_index: {nvme_func['pf_index']}, Done.*")
        else :
            print(f"* Moving NVMe Emulation function; pf_index: {nvme_func['pf_index']} - vf_index: {nvme_func['vf_index']}, Done.*")

def check_service_running(src_sock, dst_sock):
    src_spdk_ver_resp = send_recv_rpc(src_sock, spdk_script, 'spdk_get_version')
    dst_spdk_ver_resp = send_recv_rpc(dst_sock, spdk_script, 'spdk_get_version')

    if 'version' not in src_spdk_ver_resp or 'version' not in dst_spdk_ver_resp:
        print("Failed to live update - One or both of the processes are not running")
        exit(1)

#################################     Main     #################################
def main():
    """
    Entry point for the Nvidia SNAP LU(Live Upgrade).

    The function parses command-line arguments, initializes a LiveUpgradeManager instance,
    and performs live updates for VBLK and NVME functions.

    Command-line Arguments:
        -s, --src_sock: The sock of the source SNAP process.
        -d, --dst_sock: The sock of the destination SNAP process.
    """
    parser = argparse.ArgumentParser(description='Nvidia SNAP Live Upgrade')
    parser.add_argument('-s', dest='src_sock', help='Source SNAP socket name')
    parser.add_argument('-d', dest='dst_sock', help='Destination SNAP socket name')

    args = parser.parse_args()

    check_service_running(args.src_sock, args.dst_sock)

    manager = LiveUpgradeManager(args.src_sock, args.dst_sock)

    # Iterates over the VBLK physical emulation functions and performs live updates.
    # If the VBLK physical emulation function has associated virtual functions (vfs),
    # the live_update_vblk_func method is also called for each virtual function.
    for vblk_pf in manager.vblk_functions:
        manager.live_update_vblk_func(vblk_pf)
        for vf in vblk_pf['vfs']:
            manager.live_update_vblk_func(vf)
        if 'ctrl_id' in vblk_pf:
            manager.destroy_vblk_ctrl(vblk_pf)

    # Iterates over the NVME physical emulation functions and performs live updates.
    # If the NVME physical emulation function has associated virtual functions (vfs),
    # the live_update_nvme_func method is also called for each virtual function.
    for nvme_pf in manager.nvme_functions:
        manager.live_update_nvme_func(nvme_pf)
        for vf in nvme_pf['vfs']:
            manager.live_update_nvme_func(vf)
        if 'ctrl_id' in nvme_pf:
            manager.cleanup_nvme_controller(nvme_pf['ctrl_id'])

if __name__ == "__main__":
    main()
