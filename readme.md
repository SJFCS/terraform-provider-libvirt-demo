## Bridge Network Setup
Temporary configuration commands (will be lost after reboot):

1. Create and enable bridge:
   ```bash
   sudo ip link add name br0 type bridge
   sudo ip link set br0 up
   ```

2. Add physical network interface to bridge:
   ```bash
   sudo ip link set enp46s0 up  # Replace with your actual interface name
   sudo ip link set enp46s0 master br0
   ```

3. Configure bridge IP (using DHCP):
   ```bash
   # need dhclient package
   sudo dhclient br0
   ```

4. Verify configuration:
   ```bash
   ip link show type bridge  # Show bridges
   ip addr show br0         # Show bridge IP configuration
   ```

## Download Image
```bash
  wget  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img ./images/
```

## Generate SSH Key
```bash
  ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519 -N ""
```
##  Reproduction Steps
```bash
## 0.7.1 normal
terraform apply -auto-approve  
terraform destroy -auto-approve

# Update version to 0.7.4
terraform init -upgrade
terraform apply -auto-approve  
```

## cloudinit debug

https://cloudinit.readthedocs.io/en/latest/howto/debugging.html

```bash
# Check which stage has an error
sudo cloud-init status
sudo cloud-init status --long
# Check the running status of each module
sudo cloud-init analyze show

# View cloud-init main log
sudo cat /var/log/cloud-init.log
# View cloud-init output log
sudo cat /var/log/cloud-init-output.log
# View system logs using journalctl
sudo journalctl -u cloud-init
```
