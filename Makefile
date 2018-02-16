# Build the stage4 disk image.
# By Richard W.M. Jones <rjones@redhat.com>
# See README.

#----------------------------------------------------------------------
# Configuration.

# Bootloader (contains the Linux kernel as a payload).
#
# Either download this from:
#   https://fedorapeople.org/groups/risc-v/disk-images/
# or build it from:
#   https://github.com/rwmjones/fedora-riscv-kernel
bbl = bbl

# Existing stage4 is needed to build a new one.  Get a working stage4
# from https://fedorapeople.org/groups/risc-v/disk-images/ and rename
# it to this name:
old_stage4 = old-stage4-disk.img

# End of configuration.
#----------------------------------------------------------------------

all: stage4-disk.img.xz

stage4-disk.img.xz: stage4-disk.img
	rm -f $@
	xz --best -k $^
	ls -lh $@

stage4-disk.img: stage4-builder.img
	rm -f $@ $@-t build.log
	$(MAKE) boot-in-qemu DISK=stage4-builder.img |& tee build.log
# Copy out the new stage4.
	guestfish -a stage4-builder.img -i \
	    download /var/tmp/stage4-disk.img $@-t
# Sparsify it.
	virt-sparsify --inplace $@-t
	mv $@-t $@

# This is the modified stage4 which builds a new stage4.
stage4-builder.img: $(old_stage4) stage4-build-init.sh root-shell.service local.repo init.sh poweroff
	rm -f $@ $@-t
	cp $< $@-t
	guestfish -a $@-t -i \
	    rm-f /init : \
	    upload stage4-build-init.sh /init : \
	    chmod 0755 /init : \
	    copy-in $(rpmsdir) root-shell.service local.repo init.sh poweroff /var/tmp : \
	    upload local.repo /etc/yum.repos.d/local.repo : \
	    chmod 0644 /etc/yum.repos.d/local.repo
	mv $@-t $@

# Boot $(DISK) in qemu.
boot-in-qemu: $(DISK) $(bbl)
	qemu-system-riscv64 \
	    -nographic -machine virt -smp 4 -m 4G \
	    -kernel $(bbl) \
	    -append "console=ttyS0 ro root=/dev/vda init=/init" \
	    -drive file=$(DISK),format=raw,if=none,id=hd0 \
	    -device virtio-blk-device,drive=hd0 \
	    -device virtio-net-device,netdev=usernet \
	    -netdev user,id=usernet

# Build a test image and allow booting it in qemu.  Does NOT alter the
# pristine stage4 disk.
#
# To do a test build of an SRPM:
#   make boot-stage4-in-qemu COPY="/path/to/foo.src.rpm"
#   # ... inside the VM:
#   cd /var/tmp
#   dnf install @buildsys-build
#   rpmbuild --rebuild foo.src.rpm
#
# To do a test build of a source tarball:
#   make boot-stage4-in-qemu COPY="/path/to/foo.tar.gz"
#   # ... inside the VM:
#   cd /var/tmp
#   dnf install @buildsys-build
#   tar xf foo.tar.gz
#   cd foo
#   ./configure && make
#
boot-stage4-in-qemu: stage4-test.img
	if [ -n "$(COPY)" ]; then virt-copy-in -a $< $(COPY) /var/tmp; fi
	$(MAKE) boot-in-qemu DISK=$<

stage4-test.img: stage4-disk.img
	rm -f $@ $@-t
	cp $< $@-t
	mv $@-t $@

# Upload the new stage4 disk image.
upload-stage4: stage4-disk.img.xz
	scp $^ fedorapeople.org:/project/risc-v/disk-images/
	scp upload-readme fedorapeople.org:/project/risc-v/disk-images/readme.txt
	scp build.log fedorapeople.org:/project/risc-v/disk-images/

clean:
	rm -f stage4-builder.img
	rm -f *-t
	rm -f *~

distclean: clean
	rm -f stage4-disk.img
	rm -f stage4-disk.img.xz
	rm -f $(bbl)
	rm -f $(old_stage4)
