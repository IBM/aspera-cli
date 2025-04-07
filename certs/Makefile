DIR_TOP=../

include $(DIR_TOP)common.mak

CERT_FILE=$(DIR_TOP)$(shell sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC))
ADMIN_EMAIL=$(shell sed -nEe "s/ *spec.email.+'(.+)'.*/\1/p" < $(GEMSPEC))
CERT_DAYS=1100

all::
	@echo "Use one of: update new show check-key"
	@echo "Maintainer: $(ADMIN_EMAIL)"
	@echo "Certificate: $(CERT_FILE)"
	@echo "Duration: $(CERT_DAYS)"

##################################
# Gem certificate
# Update the existing certificate
update: gem_check_signing_key
	gem cert \
	--re-sign \
	--certificate $(CERT_FILE) \
	--private-key $(SIGNING_KEY) \
	--days $(CERT_DAYS)
# Create a new certificate
new: gem_check_signing_key
	gem cert \
	--build $(ADMIN_EMAIL) \
	--private-key $(SIGNING_KEY) \
	--days $(CERT_DAYS)
	mv gem-public_cert.pem $(CERT_FILE)
show:
	openssl x509 -noout -text -in $(CERT_FILE)|head -n 13
check-key: $(DIR_TMP).exists gem_check_signing_key
	openssl x509 -noout -pubkey -in $(CERT_FILE) > $(DIR_TMP)cert.pub
	@openssl rsa -pubout -passin pass:_value_ -in $(SIGNING_KEY) > $(DIR_TMP)sign.pub
	@if cmp -s $(DIR_TMP)cert.pub $(DIR_TMP)sign.pub;then echo "Ok: certificate and key match";else echo "Error: certificate and key do not match" 1>&2;exit 1;fi
