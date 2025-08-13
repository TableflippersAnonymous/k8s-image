.PHONY: output build clean upload uploadprep uploadimages uploadpxe
all: clean build output upload
clean:
	rm -rf output upload
build: clean
	docker build -t tblflp-pxe .
output: build
	mkdir -p output
	docker run --rm -v $(CURDIR)/output:/volume tblflp-pxe
uploadprep: output
	mkdir upload && cd upload && mkdir images tftp tftp/pxe && cp ../output/*.squashfs images/ && cd tftp/pxe && tar -xpf ../../../output/tftp-*.tgz
uploadimages: uploadprep
	cd upload && rsync -hPi8v --stats images/* naomi@nas-dc-1.as53546.tblflp.zone:/volume1/images/
uploadpxe: uploadprep
	cd upload && rsync -hPi8v --stats tftp/pxe/* naomi@nas-dc-1.as53546.tblflp.zone:/volume1/tftp/pxe/
upload: uploadimages uploadpxe
	rm -rf upload
