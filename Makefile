.PHONY: output build clean upload uploadpxe
all: clean build output upload
clean:
	rm -rf output
build:
	docker build -t tblflp-pxe .
output:
	mkdir -p output
	docker run --rm -v $(CURDIR)/output:/volume tblflp-pxe
upload:
	mkdir upload && cd upload && mkdir images tftp tftp/pxe && cp ../output/*.squashfs images/ && cd tftp/pxe && tar -xpf ../../../output/tftp-*.tgz
	cd upload && scp -r * cobi@nas-dc-1.as53546.tblflp.zone:/volume1/
	rm -rf upload
uploadpxe:
	mkdir upload && cd upload && mkdir images tftp tftp/pxe && cp ../output/*.squashfs images/ && cd tftp/pxe && tar -xpf ../../../output/tftp-*.tgz
	cd upload && scp -r tftp/pxe/* cobi@nas-dc-1.as53546.tblflp.zone:/volume1/tftp/pxe/
	rm -rf upload
