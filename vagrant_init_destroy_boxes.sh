#!/bin/bash -eu

BOXES_LIST=`find . -maxdepth 1 \( -name "*ubuntu*.box" -o -name "*centos*.box" -o -name "*windows*.box" \) -printf "%f\n" | sort | tr "\n" " "`
TMPDIR="/tmp/"
LOGFILE="$TMPDIR/vagrant_init_destroy_boxes.log"


vagrant_box_add() {
  vagrant box add $VAGRANT_BOX_FILE --name=${VAGRANT_BOX_NAME} --force
}

vagrant_init_up() {
  vagrant init $VAGRANT_BOX_NAME

  # Disable VagrantBox GUI
  if echo $VAGRANT_BOX_NAME | grep -q -i "virtualbox"; then
    sed -i '/config.vm.box =/a \ \ config.vm.provider "virtualbox" do |v|\n \ \ \ v.gui = false\n\ \ end' $VAGRANT_CWD/Vagrantfile
  fi

  vagrant up --provider $VAGRANT_BOX_PROVIDER
}

check_vagrant_vm() {
  local SSH_OPTIONS="-q -o StrictHostKeyChecking=no -o ControlMaster=no -o PreferredAuthentications=password -o PubkeyAuthentication=no"
  VAGRANT_VM_IP=`vagrant ssh-config | awk '/HostName/ { print $2 }'`

  case $VAGRANT_BOX_FILE in
    *windows* )
      echo "*** Running: vagrant winrm --shell powershell --command 'Get-Service ...'"
      vagrant winrm --shell powershell --command 'Get-ChildItem -Path Cert:\LocalMachine\TrustedPublisher; Get-Service | where {$_.Name -match ".*QEMU.*|.*Spice.*|.*vdservice.*|.*VBoxService.*"}; Get-WmiObject -Class Win32_Product; Get-WmiObject Win32_PnPSignedDriver | where {$_.devicename -match ".*Red Hat.*|.*VirtIO.*"} | select devicename, driverversion'
    ;;
    *centos* | *ubuntu* )
      echo "*** Running: vagrant ssh --command uptime"
      vagrant ssh --command '\
        sudo sh -c "test -x /usr/bin/apt && apt-get update 2>&1 > /dev/null && echo \"apt list -qq --upgradable\" && apt list -qq --upgradable"; \
        sudo sh -c "test -x /usr/bin/yum && yum update -q && yum list -q updates"; \
        uptime; \
        id; \
      '
      echo "*** Running: sshpass -pvagrant ssh $SSH_OPTIONS vagrant@${VAGRANT_VM_IP} 'uptime; id; sudo id'"
      sshpass -pvagrant ssh $SSH_OPTIONS vagrant@${VAGRANT_VM_IP} '\
        grep PRETTY_NAME /etc/os-release; \
        uptime; \
        id; \
        sudo id; \
      '
    ;;
  esac
}

vagrant_remove_boxes_images() {
  vagrant box remove -f $VAGRANT_BOX_NAME

  if echo $VAGRANT_BOX_NAME | grep -q -i "libvirt"; then
    sudo virsh vol-delete --pool default --vol ${VAGRANT_BOX_NAME}_vagrant_box_image_0.img
  fi
}

vagrant_destroy() {
  vagrant destroy -f
}


#######
# Main
#######

main() {
  if [ -n "$BOXES_LIST" ]; then
    test -f $LOGFILE && rm $LOGFILE
    for VAGRANT_BOX_FILE in $BOXES_LIST; do
      export VAGRANT_BOX_NAME=${VAGRANT_BOX_FILE%.*}
      export VAGRANT_BOX_PROVIDER=${VAGRANT_BOX_NAME##*-}
      export VAGRANT_CWD="$TMPDIR/$VAGRANT_BOX_NAME"

      echo -e "\n*** ${VAGRANT_BOX_FILE} [$VAGRANT_BOX_NAME] ($VAGRANT_BOX_PROVIDER)\n" | tee -a $LOGFILE
      test -d "$TMPDIR/$VAGRANT_BOX_NAME" && rm -rf "$TMPDIR/$VAGRANT_BOX_NAME"
      mkdir "$TMPDIR/$VAGRANT_BOX_NAME"

      vagrant_box_add
      vagrant_init_up

      check_vagrant_vm 2>&1 | tee -a $LOGFILE

      vagrant_destroy
      vagrant_remove_boxes_images

      rm -rf "$TMPDIR/$VAGRANT_BOX_NAME"
    done
  fi
}

main
