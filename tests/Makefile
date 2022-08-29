##################################
# Integration tests

# root folder is one level up
DIR_TOP=../

include $(DIR_TOP)common.make

all:: $(TEST_CONF_FILE_PATH) tunit tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tcos tf5
# tnagios

# "EXE_MAN" and "EXE_NOMAN" are used to call the tool in the testing environment
# "EXE_MAN" is used to generate sample commands in documentation (see in docs/Makefile)
EXE_MAN=$(EXETESTB) --warnings --config-file=$(TEST_CONF_FILE_PATH)
# "EXE_NOMAN" when the command is not needed in documentation
EXE_NOMAN=$(EXE_MAN)
# 10MB testing file generated locally
CF_LOCAL_SAMPLE_FILENAME=datafile.bin
CF_LOCAL_SAMPLE_FILEPATH=$(DIR_TMP)$(CF_LOCAL_SAMPLE_FILENAME)
CF_HSTS_FOLDER_UPLOAD := $(shell $(EXE_NOMAN) config preset get misc upload_folder 2> /dev/null || echo error)
CF_HSTS_UPLOADED_FILE=$(CF_HSTS_FOLDER_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)

clean::
	$(EXE_NOMAN) config flush

# setup local environment on Macos for preview generation testing
setupprev:
	test -d /Users/xfer || sudo /usr/sbin/sysadminctl -addUser xfer
	sudo mkdir -p /Users/xfer/docroot/previews /Users/xfer/.ssh
	sudo cp /Library/Aspera/var/aspera_tokenauth_id_rsa.pub /Users/xfer/.ssh/authorized_keys
	sudo chown -R xfer: /Users/xfer/docroot /Users/xfer/.ssh
	sudo chmod go-rwx /Users/xfer/.ssh
	sudo chmod -R +a "$$(whoami) allow write" /Users/xfer/docroot
	-sudo systemsetup -setremotelogin on
	-sudo asnodeadmin -d -u $$($(EXE_NOMAN) config preset get tst_node_preview username)
	sudo asnodeadmin -a -u $$($(EXE_NOMAN) config preset get tst_node_preview username) -p $$($(EXE_NOMAN) config preset get tst_node_preview password) -x xfer --acl-set admin,impersonation
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,$$(base64 < /dev/urandom|head -c32);absolute,AS_NULL"
	sudo asconfigurator -x "server;activity_logging,true;activity_event_logging,true;ssh_port,22"
	-sudo launchctl load  /Library/LaunchDaemons/com.aspera.asperanoded.plist
	if test $$(id -u asperadaemon) -ne $$(stat -f "%u" /Library/Logs/Aspera); then \
	  echo Fixing right;sudo chown asperadaemon: /Library/Logs/Aspera;\
	fi
	sudo launchctl stop com.aspera.asperanoded&&sleep 5
	sudo launchctl start com.aspera.asperanoded
	while ! $(EXE_NOMAN) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
	-$(EXE_NOMAN) node -N -Ptst_node_preview access_key delete $$($(EXE_NOMAN) config preset get tst_ak_preview username)
	$(EXE_NOMAN) node -N -Ptst_node_preview access_key create --value=@json:'{"id":"'$$($(EXE_NOMAN) config preset get tst_ak_preview username)'","name":"the test key","secret":"'$$($(EXE_NOMAN) config preset get tst_ak_preview password)'","storage":{"type":"local", "path":"/Users/xfer/docroot"}}'
	rm -f ~/.aspera/$(EXENAME)/persist_store/preview_iteration_transfer_localhost_testkey.txt
noderestart:
	sudo launchctl stop com.aspera.asperanoded
	sudo launchctl start com.aspera.asperanoded

###########
# Coverage
clean::
	rm -fr $(DIR_TOP)coverage
	rm -f $(DIR_TOP)simplecov.log

# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
DIR_CONNECT_DOWNLOAD=$(HOME)/Downloads
TIMESTAMP=$(shell LANG=C date)

# folder where flag files for integration tests are generated
T=$(DIR_TMP)t/
# all test cases depend on this
$(T).exists: $(DIR_TMP).exists
	#dd if=/dev/urandom of=$(CF_LOCAL_SAMPLE_FILEPATH) count=10 bs=1m
	echo 'This is a small test file' > $(CF_LOCAL_SAMPLE_FILEPATH)
	mkdir -p $(T)
	touch $@
clean::
	rm -f $(CF_LOCAL_SAMPLE_FILEPATH)
	rm -fr $(T)
$(T)unit: $(T).exists
	@echo $@
	set -x&&\
	CF_HSTS_SSH_URL=$$($(EXE_NOMAN) config preset get tst_server url) \
	CF_HSTS_SSH_USER=$$($(EXE_NOMAN) config preset get tst_server username) \
	CF_HSTS_SSH_PASS=$$($(EXE_NOMAN) config preset get tst_server password) \
	bundle exec rake spec
	@touch $@
tunit: $(T)unit
$(T)shadm: $(T).exists
	@echo $@
	$(EXE_MAN) shares admin share list
	$(EXE_MAN) shares admin user list
	$(EXE_MAN) shares admin user app_authorizations 1
	$(EXE_MAN) shares admin user share_permissions 1
	$(EXE_MAN) shares admin share list
	$(EXE_MAN) shares admin share user_permissions 9
	@touch $@
$(T)sh1: $(T).exists
	@echo $@
	$(EXE_MAN) shares repository browse /
	@touch $@
$(T)sh2: $(T).exists
	@echo $@
	set -x&&\
	shares_upload=$$($(EXE_NOMAN) config preset get misc shares_upload)&&\
	$(EXE_MAN) shares repository upload --to-folder=$${shares_upload} $(CF_LOCAL_SAMPLE_FILEPATH)&&\
	$(EXE_MAN) shares repository download --to-folder=$(DIR_TMP). $${shares_upload}/$(CF_LOCAL_SAMPLE_FILENAME)&&\
	$(EXE_MAN) shares repository delete $${shares_upload}/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)sh3: $(T).exists
	@echo $@
	set -x&&\
	shares_upload=$$($(EXE_NOMAN) config preset get misc shares_upload)&&\
	http_gw_fqdn=$$($(EXE_NOMAN) config preset get misc http_gw_fqdn_port)&&\
	$(EXE_MAN) shares repository upload --to-folder=$${shares_upload} $(CF_LOCAL_SAMPLE_FILEPATH) --transfer=httpgw --transfer-info=@json:'{"url":"https://'"$${http_gw_fqdn}"'/aspera/http-gwy/v1"}'&&\
	$(EXE_MAN) shares repository download --to-folder=$(DIR_TMP). $${shares_upload}/$(CF_LOCAL_SAMPLE_FILENAME) --transfer=httpgw --transfer-info=@json:'{"url":"https://'"$${http_gw_fqdn}"'/aspera/http-gwy/v1"}'&&\
	$(EXE_MAN) shares repository delete $${shares_upload}/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
tshares: $(T)shadm $(T)sh1 $(T)sh2 $(T)sh3

NEW_SERVER_FOLDER=$(CF_HSTS_FOLDER_UPLOAD)/server_folder
$(T)serv_browse: $(T).exists
	@echo $@
	$(EXE_MAN) server browse /
	@touch $@
$(T)serv_mkdir: $(T).exists
	@echo $@
	$(EXE_MAN) server mkdir $(NEW_SERVER_FOLDER) --logger=stdout
	@touch $@
$(T)serv_upload: $(T)serv_mkdir
	@echo $@
	$(EXE_MAN) server upload $(CF_LOCAL_SAMPLE_FILEPATH) --to-folder=$(NEW_SERVER_FOLDER) --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":1500}' --transfer-info=@json:'{"spawn_delay_sec":2.5}' --progress=multi
	set -x&&\
	recipient_email=$$($(EXE_NOMAN) config preset get misc email_external)&&\
	$(EXE_MAN) server upload --src-type=pair $(CF_LOCAL_SAMPLE_FILEPATH) $(NEW_SERVER_FOLDER)/othername --notif-to=$${recipient_email}
	$(EXE_MAN) server upload --src-type=pair --sources=@json:'["$(CF_LOCAL_SAMPLE_FILEPATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CF_LOCAL_SAMPLE_FILEPATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
	$(EXE_MAN) server upload --src-type=pair $(CF_LOCAL_SAMPLE_FILEPATH) $(CF_HSTS_FOLDER_UPLOAD)/with_options --ts=@json:'{"cipher":"aes-192-gcm","content_protection":"encrypt","content_protection_password":"_secret_here_","cookie":"biscuit","create_dir":true,"delete_before_transfer":false,"delete_source":false,"exclude_newer_than":1,"exclude_older_than":10000,"fasp_port":33001,"http_fallback":false,"multi_session":0,"overwrite":"diff+older","precalculate_job_size":true,"preserve_access_time":true,"preserve_creation_time":true,"rate_policy":"fair","resume_policy":"sparse_csum","symlink_policy":"follow"}'
	@touch $@
$(T)serv_upload_ex: $(T)serv_mkdir
	echo $(CF_LOCAL_SAMPLE_FILEPATH) > $(DIR_TMP)filelist.txt
	echo $(CF_LOCAL_SAMPLE_FILEPATH) > $(DIR_TMP)filepairlist.txt
	echo $(NEW_SERVER_FOLDER)/othername >> $(DIR_TMP)filepairlist.txt
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_file_list":"'"$(DIR_TMP)filelist.txt"'"}' --to-folder=$(NEW_SERVER_FOLDER)
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_file_pair_list":"'"$(DIR_TMP)filepairlist.txt"'"}'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-list","'"$(DIR_TMP)filelist.txt"'"]}' --to-folder=$(NEW_SERVER_FOLDER) 
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-pair-list","'"$(DIR_TMP)filepairlist.txt"'"]}'
	@touch $@
$(T)serv_md5: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server md5sum $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)serv_down_lcl: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server download $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME) --to-folder=$(DIR_TMP). --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
	@touch $@
$(T)serv_down_from_node: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server download $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME) --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --transfer=node
	@touch $@
$(T)serv_cp: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server cp $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME) $(CF_HSTS_FOLDER_UPLOAD)/200KB.2
	@touch $@
$(T)serv_mv: $(T)serv_cp
	@echo $@
	$(EXE_MAN) server mv $(CF_HSTS_FOLDER_UPLOAD)/200KB.2 $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
$(T)serv_delete: $(T)serv_mv
	@echo $@
	$(EXE_MAN) server delete $(CF_HSTS_FOLDER_UPLOAD)/to.delete
	@touch $@
$(T)serv_cleanup1: $(T).exists
	@echo $@
	$(EXE_MAN) server delete $(NEW_SERVER_FOLDER)
	@touch $@
$(T)serv_info: $(T).exists
	@echo $@
	$(EXE_MAN) server info
	@touch $@
$(T)serv_du: $(T).exists
	@echo $@
	$(EXE_MAN) server du /
	@touch $@
$(T)serv_df: $(T).exists
	@echo $@
	$(EXE_MAN) server df
	@touch $@
$(T)serv_nodeadmin: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_hstsfaspex_ssh -Plocal_user nodeadmin -- -l
	@touch $@
$(T)serv_nagios_transfer: $(T).exists
	@echo $@
	$(EXE_MAN) server health transfer --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --format=nagios 
	@touch $@
$(T)serv_nagios_hsts: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_hstsfaspex_ssh -Plocal_user health app_services --format=nagios
	@touch $@
$(T)serv_nagios_webapp: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_hstsfaspex_ssh -Plocal_user health asctlstatus --format=nagios --cmd-prefix='sudo '
	@touch $@
$(T)serv3: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_hstsfaspex_ssh -Plocal_user ctl all:status
	$(EXE_MAN) server -N -Ptst_hstsfaspex_ssh -Plocal_user configurator get_node_data
	@touch $@
$(T)serv_key: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_server_bykey -Plocal_user br /
	@touch $@
$(T)asession: $(T).exists
	@echo $@
	remote_host=$$($(EXE_NOMAN) config preset get tst_server url)&&remote_host=$${remote_host##*/}&&remote_port="$remote_host"&&remote_port=$${remote_host#*:}&&remote_host=$${remote_host%:*}&&\
	remote_user=$$($(EXE_NOMAN) config preset get tst_server username)&&\
	remote_pass=$$($(EXE_NOMAN) config preset get tst_server password)&&\
	$(DIR_BIN)asession @json:'{"remote_host":"'"$${remote_host}"'","remote_user":"'"$${remote_user}"'","ssh_port":'$${remote_port}',"remote_password":"'"$${remote_pass}"'","direction":"receive","destination_root":"$(DIR_TMP).","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@

tfasp: $(T)serv_browse $(T)serv_mkdir $(T)serv_upload $(T)serv_upload_ex $(T)serv_md5 $(T)serv_down_lcl $(T)serv_down_from_node $(T)serv_cp $(T)serv_mv $(T)serv_delete $(T)serv_cleanup1 $(T)serv_info $(T)serv_du $(T)serv_df $(T)asession $(T)serv_nodeadmin $(T)serv_nagios_hsts $(T)serv_nagios_webapp $(T)serv_nagios_transfer $(T)serv3 $(T)serv_key

$(T)fx_plst: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package list
	@touch $@
$(T)fx_psnd: $(T).exists
	@echo $@
	set -x&&\
	faspex_username=$$($(EXE_NOMAN) config preset get tst_faspex username)&&\
	email_internal_user=$$($(EXE_NOMAN) config preset get misc email_internal)&&\
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)","recipients":["'"$${email_internal_user}"'","'"$${faspex_username}"'"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
	@sleep 8
$(T)fx_prs: $(T)fx_psnd
	@echo $@
	set -x&&package_id=$$($(EXE_MAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	set -x&&package_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP). --box=sent
	@touch $@
$(T)fx_pri: $(T).exists
	@echo $@
	set -x&&package_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@
$(T)fx_prl: $(T).exists
	@echo $@
	set -x&&faspex_publink_recv_from_fxuser=$$($(EXE_NOMAN) config preset get misc faspex_publink_recv_from_fxuser)&&\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --link="$${faspex_publink_recv_from_fxuser}"
	@touch $@
$(T)fx_prall: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package recv ALL --to-folder=$(DIR_TMP). --once-only=yes
	@touch $@
$(T)fx_pslu: $(T).exists
	@echo $@
	set -x&&faspex_publink_send_to_fxuser=$$($(EXE_NOMAN) config preset get misc faspex_publink_send_to_fxuser)&&\
	$(EXE_MAN) faspex package send --link="$${faspex_publink_send_to_fxuser}" --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_psld: $(T).exists
	@echo $@
	set -x&&\
	faspex_publink_send_to_dropbox=$$($(EXE_NOMAN) config preset get misc faspex_publink_send_to_dropbox)&&\
	$(EXE_MAN) faspex package send --link="$${faspex_publink_send_to_dropbox}" --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_storage: $(T).exists
	@echo $@
	$(EXE_MAN) faspex source list
	set -x&&\
	source_name=$$($(EXE_NOMAN) config preset get misc faspex_src)&&\
	$(EXE_MAN) faspex source name "$${source_name}" info&&\
	$(EXE_MAN) faspex source name "$${source_name}" node br /
	@touch $@
$(T)fx_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) faspex health
	$(EXE_MAN) faspex me
	$(EXE_MAN) faspex address_book
	$(EXE_MAN) faspex login_methods
	@touch $@
$(T)fx_v4: $(T).exists
	@echo $@
	$(EXE_MAN) faspex v4 dropbox list
	$(EXE_MAN) faspex v4 dmembership list
	$(EXE_MAN) faspex v4 workgroup list
	$(EXE_MAN) faspex v4 wmembership list
	$(EXE_MAN) faspex v4 user list
	$(EXE_MAN) faspex v4 metadata_profile list
	@touch $@
$(T)fx_db1: $(T).exists
	@echo $@
	$(EXE_MAN) faspex dropbox list --recipient="*$${faspex_dbx}"
	set -x&&\
	faspex_dbx=$$($(EXE_NOMAN) config preset get misc faspex_dbx)&&\
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)","recipients":["*'"$${faspex_dbx}"'"]}' $(CF_LOCAL_SAMPLE_FILEPATH)&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient="*$${faspex_dbx}" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient="*$${faspex_dbx}" --to-folder=$(DIR_TMP).
	$(EXE_MAN) faspex dropbox list --recipient="*$${faspex_wkg}"
	set -x&&\
	faspex_wkg=$$($(EXE_NOMAN) config preset get misc faspex_wkg)&&\
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)","recipients":["*'"$${faspex_wkg}"'"]}' $(CF_LOCAL_SAMPLE_FILEPATH)&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient="*$${faspex_wkg}" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient="*$${faspex_wkg}" --to-folder=$(DIR_TMP).
	@touch $@
tfaspex: $(T)fx_plst $(T)fx_psnd $(T)fx_prs $(T)fx_pri $(T)fx_prl $(T)fx_pslu $(T)fx_psld $(T)fx_storage $(T)fx_prall $(T)fx_nagios $(T)fx_v4 $(T)fx_db1

$(T)cons1: $(T).exists
	@echo $@
	$(EXE_MAN) console transfer current list 
	@touch $@
$(T)cons2: $(T).exists
	@echo $@
	$(EXE_MAN) console transfer smart list 
	@touch $@
$(T)cons3: $(T).exists
	@echo $@
	set -x&&\
	job_id=$$($(EXE_NOMAN) config preset get misc console_smart_id)&&\
	file_name=$$($(EXE_NOMAN) config preset get misc console_smart_file)&&\
	$(EXE_MAN) console transfer smart sub $${job_id} @json:'{"source":{"paths":["'"$${file_name}"'"]},"source_type":"user_selected"}'
	@touch $@
tconsole: $(T)cons1 $(T)cons2 $(T)cons3

$(T)nd1: $(T).exists
	@echo $@
	$(EXE_MAN) node info --fpac='function FindProxyForURL(url,host){return "DIRECT"}'
	$(EXE_MAN) node license
	$(EXE_MAN) node api_details
	$(EXE_MAN) node browse / -r
	$(EXE_MAN) node search / --value=@json:'{"sort":"mtime"}'
	$(EXE_MAN) node space /
	-$(EXE_MAN) node delete /todelete
	$(EXE_MAN) node mkdir /todelete
	$(EXE_MAN) node mklink /todelete /tdlink
	$(EXE_MAN) node mkfile /delfile1 "hello world"
	$(EXE_MAN) node rename / delfile1 delfile
	$(EXE_MAN) node delete @list:,/todelete,/tdlink,/delfile
	@touch $@
$(T)nd2: $(T).exists
	@echo $@
	$(EXE_MAN) node upload $(CF_LOCAL_SAMPLE_FILEPATH) --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}'
	$(EXE_MAN) node upload $(CF_LOCAL_SAMPLE_FILEPATH) --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}' --token-type=hybrid
	$(EXE_MAN) node download $(CF_HSTS_UPLOADED_FILE) --to-folder=$(DIR_TMP).
	$(EXE_MAN) node download $(CF_HSTS_UPLOADED_FILE) --to-folder=$(DIR_TMP). --token-type=hybrid
	$(EXE_MAN) node delete $(CF_HSTS_UPLOADED_FILE)
	@touch $@
$(T)nd_2_nd_xfer: $(T).exists
	@echo $@
	set -x&&node_url=$$($(EXE_NOMAN) config preset get tst_node url)&&\
	node_user=$$($(EXE_NOMAN) config preset get tst_node username)&&\
	node_pass=$$($(EXE_NOMAN) config preset get tst_node password)&&\
	$(EXE_MAN) node upload --to-folder="$(CF_HSTS_FOLDER_UPLOAD)" --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"'"$${node_url}"'","username":"'"$${node_user}"'","password":"'"$${node_pass}"'"}'
	$(EXE_MAN) node delete $(CF_HSTS_FOLDER_UPLOAD)/10MB.1
	@touch $@
$(T)nd4: $(T).exists
	@echo $@
	$(EXE_MAN) node service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 2
	$(EXE_MAN) node service delete service1
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node service list
	@touch $@
# test creation of access key
$(T)nd5: $(T).exists
	@echo $@
	$(EXE_MAN) node -N -Ptst_node_preview access_key create --value=@json:'{"id":"aoc_1","storage":{"type":"local","path":"/"}}'
	sleep 2
	$(EXE_MAN) node -N -Ptst_node_preview access_key delete aoc_1
	@touch $@
$(T)nd6: $(T).exists
	@echo $@
	$(EXE_MAN) node transfer list --value=@json:'{"active_only":true}'
	@touch $@
$(T)nd7: $(T).exists
	@echo $@
	$(EXE_MAN) node basic_token
	@touch $@
$(T)nd8: $(T).exists
	@echo $@
	$(EXE_MAN) node upload --username=@preset:misc.aoc_ak_name --password=@preset:misc.aoc_ak_secret $(CF_LOCAL_SAMPLE_FILEPATH) --token-type=basic
	@touch $@
$(T)nd_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) node health
	@touch $@
$(T)nd_ak: $(T).exists
	@echo $@
	$(EXE_MAN) node access_key list
	$(EXE_MAN) node access_key do @preset:misc.aoc_ak_name br /
	@touch $@
tnode: $(T)nd1 $(T)nd2 $(T)nd_2_nd_xfer $(T)nd4 $(T)nd5 $(T)nd6 $(T)nd7 $(T)nd8 $(T)nd_nagios $(T)nd_ak

$(T)aocg1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc -N servers
	set -x&&\
	aoc_user_email=$$($(EXE_NOMAN) config preset get misc aoc_user_email)&&\
	$(EXE_MAN) aoc -N remind --username=$${aoc_user_email}
	@touch $@
$(T)aocg2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc bearer_token --display=data --scope=user:all
	@touch $@
$(T)aocg3: $(T).exists
	@echo $@
	$(EXE_MAN) aoc organization
	@touch $@
$(T)aocg4: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user workspaces list
	@touch $@
$(T)aocg5: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user profile show
	@touch $@
$(T)aocg6: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user profile modify @json:'{"name":"dummy change"}'
	@touch $@
$(T)aocg7: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages shared_inboxes list
	@touch $@
$(T)aocg8: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user workspaces current
	@touch $@
taocgen: $(T)aocg1 $(T)aocg2 $(T)aocg3 $(T)aocg4 $(T)aocg5 $(T)aocg6 $(T)aocg7 $(T)aocg8
$(T)aocfbr: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files browse /
	@touch $@
$(T)aocfbt: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files bearer_token_node / --cache-tokens=no
	@touch $@
$(T)aocffin: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files find / --value='\.partial$$'
	@touch $@
$(T)aocfmkd: $(T).exists
	@echo $@
	-$(EXE_NOMAN) aoc files delete /testsrc
	$(EXE_MAN) aoc files mkdir /testsrc
	@touch $@
$(T)aocfren: $(T).exists
	@echo $@
	-$(EXE_NOMAN) aoc files delete /testdst
	$(EXE_NOMAN) aoc files mkdir /somefolder
	$(EXE_MAN) aoc files rename /somefolder testdst
	@touch $@
$(T)aocfupl: $(T)aocfmkd
	@echo $@
	$(EXE_MAN) aoc files upload --to-folder=/testsrc $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocftr: $(T)aocfupl $(T)aocfren
	@echo $@
	$(EXE_MAN) aoc files transfer --from-folder=/testsrc --to-folder=/testdst $(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)aocndinf: $(T).exists
	@echo $@
	set -x&&\
	other_workspace=$$($(EXE_NOMAN) config preset get misc aoc_workspace2)&&\
	$(EXE_MAN) aoc files node_info --workspace="$${other_workspace}" /myfolder --format=json --display=data | $(EXE_MAN) aoc files upload Test.pdf --transfer=node --transfer-info=@json:@stdin:
	@touch $@
$(T)aocfdel: $(T)aocfren
	@echo $@
	$(EXE_MAN) aoc files delete /testsrc
	@touch $@
$(T)aocfbearnode: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files bearer /
	@touch $@
$(T)aocfdown: $(T).exists
	@echo $@
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	$(EXE_MAN) aoc files download --transfer=connect /200KB.1
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	@touch $@
$(T)aocfhttpd: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files http_node_download --to-folder=$(DIR_TMP). /200KB.1
	@touch $@
$(T)aocfv3inf: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files v3 info
	@touch $@
$(T)aocffid: $(T).exists
	@echo $@
	set -x&&\
	file_id=$$($(EXE_NOMAN) aoc files br /200KB.1 --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) aoc files file show $${file_id}
	@touch $@
$(T)aocfpub: $(T).exists
	@echo $@
	set -x&&\
	aoc_publink_folder=$$($(EXE_NOMAN) config preset get misc aoc_publink_folder)&&\
	$(EXE_MAN) aoc files browse / -N --link=$${aoc_publink_folder}
	set -x&&\
	aoc_publink_folder=$$($(EXE_NOMAN) config preset get misc aoc_publink_folder)&&\
	$(EXE_MAN) aoc files upload -N --to-folder=/ $(CF_LOCAL_SAMPLE_FILEPATH) --link=$${aoc_publink_folder}
	@touch $@
$(T)aocshlk1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
	@touch $@
$(T)aocshlk2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link create --to-folder=/testdst --value=private
	@touch $@
$(T)aocshlk3: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link create --to-folder=/testdst --value=public
	@touch $@
taocf: $(T)aocfbr $(T)aocfbt $(T)aocffin $(T)aocfmkd $(T)aocfren $(T)aocfupl $(T)aocftr $(T)aocndinf $(T)aocfdel $(T)aocfbearnode $(T)aocfdown $(T)aocfhttpd $(T)aocfv3inf $(T)aocffid $(T)aocfpub $(T)aocshlk1 $(T)aocshlk2 $(T)aocshlk3
$(T)aocp1: $(T).exists
	@echo $@
	set -x&&\
	email_internal_user=$$($(EXE_NOMAN) config preset get misc email_internal)&&\
	email_external_user=$$($(EXE_NOMAN) config preset get misc email_external)&&\
	$(EXE_MAN) aoc packages send --value=@json:'{"name":"Test Package $(TIMESTAMP)","recipients":["'"$${email_internal_user}"'"],"note":"my note"}' $(CF_LOCAL_SAMPLE_FILEPATH)&&\
	$(EXE_MAN) aoc packages send --value=@json:'{"name":"Test Package $(TIMESTAMP)","recipients":["'"$${email_external_user}"'"]}' --new-user-option=@json:'{"package_contact":true}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocp2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages list
	@touch $@
$(T)aocp3: $(T).exists
	@echo $@
	set -x&&package_id=$$($(EXE_NOMAN) aoc packages list --format=csv --fields=id --display=data|head -n 1)&&\
	$(EXE_MAN) aoc packages recv "$${package_id}" --to-folder=$(DIR_TMP).&&\
	$(EXE_MAN) aoc packages browse "$${package_id}" /contents
	@touch $@
$(T)aocp4: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages recv ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345
	@touch $@
$(T)aocp5: $(T).exists
	@echo $@
	set -x&&\
	aoc_publink_recv_from_aocuser=$$($(EXE_NOMAN) config preset get misc aoc_publink_recv_from_aocuser)&&\
	$(EXE_MAN) aoc org -N --link=$${aoc_publink_recv_from_aocuser}
	@touch $@
$(T)aocp6: $(T).exists
	@echo $@
	set -x&&\
	aoc_publink_send_shd_inbox=$$($(EXE_NOMAN) config preset get misc aoc_publink_send_shd_inbox)&&\
	$(EXE_MAN) aoc packages send -N --value=@json:'{"name":"Test Package $(TIMESTAMP)"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$${aoc_publink_send_shd_inbox}
	@touch $@
$(T)aocp7: $(T).exists
	@echo $@
	set -x&&\
	aoc_publink_send_aoc_user=$$($(EXE_NOMAN) config preset get misc aoc_publink_send_aoc_user)&&\
	aoc_publink_send_use_pass=$$($(EXE_NOMAN) config preset get misc aoc_publink_send_use_pass)&&\
	$(EXE_MAN) aoc packages send -N --value=@json:'{"name":"Test Package $(TIMESTAMP)"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$${aoc_publink_send_aoc_user} --password=$${aoc_publink_send_use_pass}
	@touch $@
$(T)aocp8: $(T).exists
	@echo $@
	set -x&&\
	aoc_shbx_ws=$$($(EXE_NOMAN) config preset get misc aoc_shbx_ws)&&\
	aoc_shbx_name=$$($(EXE_NOMAN) config preset get misc aoc_shbx_name)&&\
	$(EXE_MAN) aoc packages send --workspace="$${aoc_shbx_ws}" --value=@json:'{"name":"Test Package $(TIMESTAMP)","recipients":["'"$${aoc_shbx_name}"'"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	set -x&&\
	aoc_shbx_ws=$$($(EXE_NOMAN) config preset get misc aoc_shbx_ws)&&\
	aoc_shbx_name=$$($(EXE_NOMAN) config preset get misc aoc_shbx_meta)&&\
	$(EXE_MAN) aoc packages send --workspace="$${aoc_shbx_ws}" --value=@json:'{"name":"Test Package $(TIMESTAMP)","recipients":["'"$${aoc_shbx_name}"'"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
	set -x&&\
	aoc_shbx_ws=$$($(EXE_NOMAN) config preset get misc aoc_shbx_ws)&&\
	aoc_shbx_name=$$($(EXE_NOMAN) config preset get misc aoc_shbx_meta)&&\
	$(EXE_MAN) aoc packages send --workspace="$${aoc_shbx_ws}" --value=@json:'{"name":"Test Package $(TIMESTAMP)","recipients":["'"$${aoc_shbx_name}"'"],"metadata":{"Project Id":"456","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocp9: $(T).exists
	@echo $@
	set -x&&\
	aoc_shbx_ws=$$($(EXE_NOMAN) config preset get misc aoc_shbx_ws)&&\
	aoc_shbx_name=$$($(EXE_NOMAN) config preset get misc aoc_shbx_name)&&\
	$(EXE_MAN) aoc packages list --query=@json:'{"dropbox_name":"'"$${aoc_shbx_name}"'","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
	@touch $@
taocp: $(T)aocp1 $(T)aocp2 $(T)aocp3 $(T)aocp4 $(T)aocp5 $(T)aocp5 $(T)aocp6 $(T)aocp7 $(T)aocp8 $(T)aocp9
$(T)aoc8: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace list
	@touch $@
$(T)aoc9: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v3 events
	@touch $@
$(T)aoc11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
$(T)aoc12: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node v3 name @preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret access_key delete testsub1
	@touch $@
$(T)aoc9b: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v4 browse /
	@touch $@
$(T)aoc10: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v4 mkdir /folder1
	@touch $@
$(T)aoc13: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v4 delete /folder1
	@touch $@
$(T)aoc14: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
$(T)aoc15: $(T).exists
	@echo $@
	set -x&&\
	recipient_email=$$($(EXE_NOMAN) config preset get misc email_external)&&\
	$(EXE_MAN) aoc admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}' --notif-to=$${recipient_email} --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
	@touch $@
$(T)aocarself: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin res self show
	$(EXE_MAN) aoc admin res organization show
	$(EXE_MAN) aoc admin res user list
	$(EXE_MAN) aoc admin res group list
	$(EXE_MAN) aoc admin res client list
	$(EXE_MAN) aoc admin res contact list
	$(EXE_MAN) aoc admin res dropbox list
	$(EXE_MAN) aoc admin res node list
	$(EXE_MAN) aoc admin res operation list
	$(EXE_MAN) aoc admin res package list --http-options=@json:'{"read_timeout":120.0}'
	$(EXE_MAN) aoc admin res saml_configuration list
	$(EXE_MAN) aoc admin res dropbox_membership list
	$(EXE_MAN) aoc admin res workspace_membership list
	$(EXE_MAN) aoc admin res short_link list
	$(EXE_MAN) aoc admin res application list
	$(EXE_MAN) aoc admin res client_access_key list
	$(EXE_MAN) aoc admin res kms_profile list
	@touch $@
$(T)aoccltreg: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin res client_registration_token create @json:'{"data":{"name":"test_client_reg1","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}'
	$(EXE_MAN) aoc admin res client_registration_token list
	clt_reg_id=$$($(EXE_NOMAN) aoc admin res client_registration_token list --fields=ALL --select=@json:'{"data.name":"test_client_reg1"}' --fields=id --format=csv --display=data|tail -n 1)&&\
	$(EXE_MAN) aoc admin res client_registration_token delete $${clt_reg_id}
	@touch $@
taocadm: $(T)aoc8 $(T)aoc9 $(T)aoc9b $(T)aoc10 $(T)aoc11 $(T)aoc12 $(T)aoc13 $(T)aoc14 $(T)aoc15 $(T)aocarself $(T)aoccltreg
$(T)aocat4: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats cluster list
	@touch $@
$(T)aocat5: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats cluster clouds
	@touch $@
$(T)aocat6: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats cluster show --cloud=aws --region=eu-west-1
	@touch $@
$(T)aocat7: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(T)aocat8: $(T).exists
	@echo $@
	set -x&&\
	icos_bucket_region=$$($(EXE_NOMAN) config preset get misc icos_bucket_region)&&\
	icos_bucket_name=$$($(EXE_NOMAN) config preset get misc icos_bucket_name)&&\
	icos_bucket_key=$$($(EXE_NOMAN) config preset get misc icos_bucket_key)&&\
	icos_bucket_secret=$$($(EXE_NOMAN) config preset get misc icos_bucket_secret)&&\
	$(EXE_MAN) aoc admin ats access_key create --cloud=softlayer --region=$${icos_bucket_region} --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"'"$${icos_bucket_name}"'","credentials":{"access_key_id":"'"$${icos_bucket_key}"'","secret_access_key":"'"$${icos_bucket_secret}"'"},"path":"/"}}'
	@touch $@
$(T)aocat9: $(T).exists
	@echo $@
	-set -x&&\
	aws_bucket_region=$$($(EXE_NOMAN) config preset get misc aws_bucket_region)&&\
	aws_bucket_name=$$($(EXE_NOMAN) config preset get misc aws_bucket_name)&&\
	aws_bucket_key=$$($(EXE_NOMAN) config preset get misc aws_bucket_key)&&\
	aws_bucket_secret=$$($(EXE_NOMAN) config preset get misc aws_bucket_secret)&&\
	$(EXE_MAN) aoc admin ats access_key create --cloud=aws --region=$${aws_bucket_region} --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'"$${aws_bucket_name}"'","credentials":{"access_key_id":"'"$${aws_bucket_key}"'","secret_access_key":"'"$${aws_bucket_secret}"'"},"path":"/"}}'
	@touch $@
$(T)aocat10: $(T).exists
	@echo $@
	-$(EXE_MAN) aoc admin ats access_key list --fields=name,id
	@touch $@
$(T)aocat11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats access_key node akibmcloud --secret=somesecret browse /
	@touch $@
$(T)aocat13: $(T).exists
	@echo $@
	-$(EXE_MAN) aoc admin ats access_key delete akibmcloud
	@touch $@
taocts: $(T)aocat4 $(T)aocat5 $(T)aocat6 $(T)aocat7 $(T)aocat8 $(T)aocat9 $(T)aocat10 $(T)aocat11 $(T)aocat13
$(DIR_TMP)wf_id.txt: $(T)aocauto1
	$(EXE_MAN) aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data > $@
$(T)aocauto1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc automation workflow create --value=@json:'{"name":"test_workflow"}'
	@touch $@
$(T)aocauto2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc automation workflow list
	$(EXE_MAN) aoc automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@touch $@
$(T)aocauto3: $(DIR_TMP)wf_id.txt
	@echo $@
	set -x&&wf_id=$$(cat $(DIR_TMP)wf_id.txt)&&\
	$(EXE_MAN) aoc automation workflow action $${wf_id} create --value=@json:'{"name":"toto"}' | tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@touch $@
$(T)aocauto10: $(DIR_TMP)wf_id.txt
	@echo $@
	set -x&&wf_id=$$(cat $(DIR_TMP)wf_id.txt)&&\
	$(EXE_MAN) aoc automation workflow delete $${wf_id}
	rm -f $(T)wf.id
	@touch $@
taocauto: $(T)aocauto1 $(T)aocauto2 $(T)aocauto3 $(T)aocauto10
taoc: taocgen taocf taocp taocadm taocts taocauto

$(T)o1: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator info
	@touch $@
$(T)o2: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow list
	@touch $@
$(T)o3: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow status ALL
	@touch $@
$(T)o4: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow inputs @preset:misc.orch_workflow_id
	@touch $@
$(T)o5: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow status @preset:misc.orch_workflow_id
	@touch $@
$(T)o6: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow start @preset:misc.orch_workflow_id --params=@json:'{"Param":"world !"}'
	@touch $@
$(T)o7: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow start @preset:misc.orch_workflow_id --params=@json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
	@touch $@
$(T)o8: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator plugins
	@touch $@
$(T)o9: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator processes
	@touch $@
$(T)o10: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow details @preset:misc.orch_workflow_id
	$(EXE_MAN) orchestrator workflow export @preset:misc.orch_workflow_id
	@touch $@

torc: $(T)o1 $(T)o2 $(T)o3 $(T)o4 $(T)o5 $(T)o6 $(T)o7 $(T)o8 $(T)o9 $(T)o10

$(T)at4: $(T).exists
	@echo $@
	$(EXE_MAN) ats cluster list
	@touch $@
$(T)at5: $(T).exists
	@echo $@
	$(EXE_MAN) ats cluster clouds
	@touch $@
$(T)at6: $(T).exists
	@echo $@
	$(EXE_MAN) ats cluster show --cloud=aws --region=eu-west-1
	@touch $@
$(T)at7: $(T).exists
	@echo $@
	$(EXE_MAN) ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
$(T)at2: $(T).exists
	@echo $@
	$(EXE_MAN) ats api_key instances
	@touch $@
$(T)at1: $(T).exists
	@echo $@
	$(EXE_MAN) ats api_key list
	@touch $@
$(T)at3: $(T).exists
	@echo $@
	$(EXE_MAN) ats api_key create
	@touch $@
$(T)at8: $(T).exists
	@echo $@
	set -x&&\
	icos_bucket_region=$$($(EXE_NOMAN) config preset get misc icos_bucket_region)&&\
	icos_bucket_name=$$($(EXE_NOMAN) config preset get misc icos_bucket_name)&&\
	icos_bucket_key=$$($(EXE_NOMAN) config preset get misc icos_bucket_key)&&\
	icos_bucket_secret=$$($(EXE_NOMAN) config preset get misc icos_bucket_secret)&&\
	$(EXE_MAN) ats access_key create --cloud=softlayer --region=$${icos_bucket_region} --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"'"$${icos_bucket_name}"'","credentials":{"access_key_id":"'"$${icos_bucket_key}"'","secret_access_key":"'"$${icos_bucket_secret}"'"},"path":"/"}}'
	@touch $@
$(T)at9: $(T).exists
	@echo $@
	-set -x&&\
	aws_bucket_region=$$($(EXE_NOMAN) config preset get misc aws_bucket_region)&&\
	aws_bucket_name=$$($(EXE_NOMAN) config preset get misc aws_bucket_name)&&\
	aws_bucket_key=$$($(EXE_NOMAN) config preset get misc aws_bucket_key)&&\
	aws_bucket_secret=$$($(EXE_NOMAN) config preset get misc aws_bucket_secret)&&\
	$(EXE_MAN) ats access_key create --cloud=aws --region=$${aws_bucket_region} --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'"$${aws_bucket_name}"'","credentials":{"access_key_id":"'"$${aws_bucket_key}"'","secret_access_key":"'"$${aws_bucket_secret}"'"},"path":"/"}}'
	@touch $@
$(T)at10: $(T).exists
	@echo $@
	-$(EXE_MAN) ats access_key list --fields=name,id
	@touch $@
$(T)at11: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key node akibmcloud browse / --secret=somesecret
	@touch $@
$(T)at12: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key cluster akibmcloud --secret=somesecret
	@touch $@
$(T)at13: $(T).exists
	$(EXE_MAN) ats access_key delete akibmcloud
	@touch $@
$(T)at14: $(T).exists
	@echo $@
	-$(EXE_MAN) ats access_key delete ak_aws
	@touch $@

tats: $(T)at4 $(T)at5 $(T)at6 $(T)at7 $(T)at2 $(T)at1 $(T)at3 $(T)at8 $(T)at9 $(T)at10 $(T)at11 $(T)at12 $(T)at13 $(T)at14

$(T)co1: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp show
	$(EXE_MAN) config ascp spec
	$(EXE_MAN) config ascp errors
	@touch $@
$(T)co2: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp products list
	@touch $@
$(T)co3: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect list
	@touch $@
$(T)co4: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect info 'Aspera Connect for Windows'
	@touch $@
$(T)co5: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' list
	@touch $@
$(T)co6: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' download 'Windows Installer' --to-folder=$(DIR_TMP).
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' open documentation
	@touch $@
$(T)co7: $(T).exists
	@echo $@
	-rm -fr $(T)sdk_test_dir
	$(EXE_MAN) config ascp install --sdk-folder=$(T)sdk_test_dir
	@touch $@
$(T)co8: $(T)co7
	@echo $@
	$(EXE_MAN) config ascp info --sdk-folder=$(T)sdk_test_dir
	@touch $@
tcon: $(T)co1 $(T)co2 $(T)co3 $(T)co4 $(T)co5 $(T)co6 $(T)co7 $(T)co8

$(T)sy1: $(T).exists
	@echo $@
	$(EXE_MAN) node async list
	@touch $@
$(T)sy2: $(T).exists
	@echo $@
	$(EXE_MAN) node async show 1
	$(EXE_MAN) node async show ALL
	@touch $@
$(T)sy3: $(T).exists
	@echo $@
	$(EXE_MAN) node async counters 1
	@touch $@
$(T)sy4: $(T).exists
	@echo $@
	$(EXE_MAN) node async bandwidth 1
	@touch $@
$(T)sy5: $(T).exists
	@echo $@
	$(EXE_MAN) node async files 1
	@touch $@
tnsync: $(T)sy1 $(T)sy2 $(T)sy3 $(T)sy4 $(T)sy5

TEST_CONFIG=$(DIR_TMP)sample.conf
EXETESTC=$(EXETESTB) --config-file=$(TEST_CONFIG)
clean::
	rm -f $(TEST_CONFIG)
$(T)conf_id_1: $(T).exists
	@echo $@
	$(EXETESTC) config preset set conf_name param value
	@touch $@
$(T)conf_id_2: $(T).exists
	@echo $@
	$(EXETESTC) config preset show conf_name
	@touch $@
$(T)conf_id_3: $(T).exists
	@echo $@
	$(EXETESTC) config preset set default shares conf_name
	@touch $@
$(T)conf_id_4: $(T).exists
	@echo $@
	$(EXETESTC) config preset delete conf_name
	@touch $@
$(T)conf_id_5: $(T).exists
	@echo $@
	$(EXETESTC) config preset initialize conf_name @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
$(T)conf_id_6: $(T).exists
	@echo $@
	$(EXETESTC) config preset update conf_name --p1=v1 --p2=v2
	@touch $@
$(T)conf_open: $(T).exists
	@echo $@ open configuration file in text editor
	$(EXETESTC) config open
	@touch $@
$(T)conf_list: $(T).exists
	@echo $@
	$(EXETESTC) config list
	@touch $@
$(T)conf_over: $(T).exists
	@echo $@
	$(EXETESTC) config overview
	$(EXETESTC) config ascp use /usr/bin/ascp
	@touch $@
$(T)conf_vault: $(T).exists
	$(EXETESTC) config vault init --value=config
	$(EXETESTC) config vault set --url=https://example.com --username=toto --value="my prefered secret" 12345678
	$(EXETESTC) config vault list
	$(EXETESTC) config vault get --url=https://example.com --username=toto
	$(EXETESTC) config vault delete --url=https://example.com --username=toto
	@touch $@
$(T)conf_help: $(T).exists
	@echo $@
	$(EXE_NOMAN) -h
	@touch $@
$(T)conf_open_err: $(T).exists
	@echo $@
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-$(EXETESTC) config open
	@touch $@
$(T)conf_plugins: $(T).exists
	@echo $@
	$(EXE_MAN) config plugin list
	$(EXE_MAN) config plugin create mycommand $(T)
	$(EXE_NOMAN) mycommand --plugin-folder=$(T)
	@touch $@
$(T)conf_export: $(T).exists
	@echo $@
	-$(EXE_MAN) config export
	@touch $@
SAMPLE_CONFIG_FILE=$(DIR_TMP)tmp_config.yml
$(T)conf_wizard_org: $(T).exists
	@echo $@
	$(EXE_MAN) config flush_tokens
	set -x&&\
	aoc_org=$$($(EXE_NOMAN) config preset get misc aoc_org)&&\
	aoc_user_email=$$($(EXE_NOMAN) config preset get misc aoc_user_email)&&\
	$(EXE_MAN) config wiz --url=https://$${aoc_org}.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath= --username=$${aoc_user_email} --test-mode=yes --use-generic-client=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_wizard_gen: $(T).exists
	@echo $@
	$(EXE_MAN) config flush_tokens
	set -x&&\
	aoc_org=$$($(EXE_NOMAN) config preset get misc aoc_org)&&\
	aoc_user_email=$$($(EXE_NOMAN) config preset get misc aoc_user_email)&&\
	$(EXE_MAN) config wiz --url=https://$${aoc_org}.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath= --username=$${aoc_user_email} --test-mode=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_detect: $(T).exists
	@echo $@
	set -x&&\
	aoc_org=$$($(EXE_NOMAN) config preset get misc aoc_org)&&\
	faspex_url=$$($(EXE_NOMAN) config preset get tst_faspex url)&&\
	node_url=$$($(EXE_NOMAN) config preset get tst_node url)&&\
	$(EXE_MAN) config detect --url=https://$${aoc_org}.ibmaspera.com&&\
	$(EXE_MAN) config detect --url=$${faspex_url}&&\
	$(EXE_MAN) config detect --url=$${node_url}
	@touch $@
$(T)conf_genkey: $(T).exists
	@echo $@
	$(EXE_MAN) config genkey $(DIR_TMP)mykey
	@touch $@
$(T)conf_smtp: $(T).exists
	@echo $@
	set -x&&\
	recipient_email=$$($(EXE_NOMAN) config preset get misc email_external)&&\
	$(EXE_MAN) config email_test --notif-to=$${recipient_email}
	@touch $@
$(T)conf_pac: $(T).exists
	@echo $@
	$(EXE_MAN) config proxy_check --fpac=@file:$(DIR_TOP)examples/proxy.pac https://eudemo.asperademo.com
	@touch $@
$(T)conf_check_gem: $(T).exists
	@echo $@
	$(EXE_MAN) config check_update
	@touch $@
$(T)conf_doc: $(T).exists
	@echo $@
	$(EXE_MAN) config doc
	$(EXE_MAN) config doc transfer-parameters
	@touch $@
$(T)conf_echo: $(T).exists
	@echo $@
	$(EXE_MAN) config echo 'hello'
	$(EXE_MAN) config echo @uri:/etc/hosts
	$(EXE_MAN) config echo @uri:file:/etc/hosts
	$(EXE_MAN) config echo @uri:http://www.ibm.com
	$(EXE_MAN) config echo @uri:https://www.ibm.com
	$(EXE_MAN) config echo @base64:SGVsbG8gV29ybGQK
	$(EXE_MAN) config echo @list:,1,2,3
	$(EXE_MAN) config echo @env:USER
	$(EXE_MAN) config echo @val:@file:yo
	echo $$'1\n2\n3'|$(EXE_MAN) config echo @lines:@stdin:
	echo $$'t1,t2,t3\na,b,d\nd,e,f'|$(EXE_MAN) config echo @csvt:@stdin:
	ruby -rzlib -e'puts Zlib::Deflate.deflate("Hello World")'|$(EXE_MAN) config echo @zlib:@stdin:
	@touch $@
tconf: $(T)conf_id_1 $(T)conf_id_2 $(T)conf_id_3 $(T)conf_id_4 $(T)conf_id_5 $(T)conf_id_6 $(T)conf_open $(T)conf_list $(T)conf_over $(T)conf_vault $(T)conf_help $(T)conf_open_err $(T)conf_plugins $(T)conf_export $(T)conf_wizard_org $(T)conf_wizard_gen $(T)conf_detect $(T)conf_genkey $(T)conf_smtp $(T)conf_pac $(T)conf_check_gem $(T)conf_doc $(T)conf_echo

$(T)prev_check: $(T).exists
	@echo $@
	$(EXE_MAN) preview check --skip-types=office
	@touch $@
$(T)prev_dcm: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png @preset:misc.file_dcm --log-level=debug
	@touch $@
$(T)prev_pdf: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png @preset:misc.file_pdf --log-level=debug
	@touch $@
$(T)prev_docx: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png @preset:misc.file_docx --log-level=debug
	@touch $@
$(T)prev_mxf_blend: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 @preset:misc.file_mxf --video-conversion=blend --log-level=debug
	@touch $@
$(T)prev_mxf_png_fix: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png @preset:misc.file_mxf --video-png-conv=fixed --log-level=debug
	@touch $@
$(T)prev_mxf_png_ani: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png @preset:misc.file_mxf --video-png-conv=animated --log-level=debug
	@touch $@
$(T)prev_mxf_reencode: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 @preset:misc.file_mxf --video-conversion=reencode --log-level=debug
	@touch $@
$(T)prev_mxf_clips: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 @preset:misc.file_mxf --video-conversion=clips --log-level=debug
	@touch $@
$(T)prev_events: $(T).exists
	@echo $@
	$(EXE_NOMAN) -Ptst_ak_preview node upload @preset:misc.file_mxf @preset:misc.file_docx --ts=@json:'{"target_rate_kbps":1000000}' --token-type=hybrid
	sleep 4
	$(EXE_MAN) preview trevents --once-only=yes --skip-types=office --log-level=info
	@touch $@
$(T)prev_scan: $(T).exists
	@echo $@
	$(EXE_MAN) preview scan --skip-types=office --log-level=info
	@touch $@
$(T)prev_folder: $(T).exists
	@echo $@
	$(EXE_MAN) preview folder 1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
	@touch $@

tprev: $(T)prev_check $(T)prev_dcm $(T)prev_pdf $(T)prev_docx $(T)prev_mxf_png_fix $(T)prev_mxf_png_ani $(T)prev_mxf_blend $(T)prev_mxf_reencode $(T)prev_mxf_clips $(T)prev_events $(T)prev_scan
thot:
	rm -fr source_hot
	mkdir source_hot
	-$(EXE_MAN) server delete $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	$(EXE_MAN) server mkdir $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	echo hello > source_hot/newfile
	$(EXE_MAN) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	sleep 10
	$(EXE_MAN) server upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD)/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse $(CF_HSTS_FOLDER_UPLOAD)/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@
$(T)sync1: $(T).exists
	@echo $@
	mkdir -p $(DIR_TMP)contents
	cp $(CF_LOCAL_SAMPLE_FILEPATH) $(DIR_TMP)contents
	set -x&&\
	remote_host=$$($(EXE_NOMAN) config preset get tst_server_bykey url)&&\
	remote_host=$${remote_host##*/}&&\
	remote_port=$${remote_host#*:}&&\
	remote_host=$${remote_host%:*}&&\
	remote_user=$$($(EXE_NOMAN) config preset get misc syncuser)&&\
	local_user_key=$$($(EXE_NOMAN) config preset get local_user ssh_keys)&&\
	$(EXE_MAN) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"$(DIR_TMP)contents","host":"'"$${remote_host}"'","tcp_port":33001,"user":"'"$${remote_user}"'","private_key_path":"'"$${local_user_key}"'"}]}'
	@touch $@
tsync: $(T)sync1
$(T)sdk1: $(T).exists
	@echo $@
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/transfer.rb
	@touch $@
$(T)sdk2: $(T).exists
	@echo $@
	set -x&&url=$$($(EXE_NOMAN) config preset get tst_aoc1 url)&&\
	user=$$($(EXE_NOMAN) config preset get tst_aoc1 username)&&\
	keypath=$$($(EXE_NOMAN) config preset get tst_aoc1 private_key)&&\
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/aoc.rb $${url} $${user} "$${keypath}"
	@touch $@
$(T)sdk3: $(T).exists
	@echo $@
	set -x&&url=$$($(EXE_NOMAN) config preset get tst_faspex url)&&\
	user=$$($(EXE_NOMAN) config preset get tst_faspex username)&&\
	pass=$$($(EXE_NOMAN) config preset get tst_faspex password)&&\
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/faspex4.rb $${url} $${user} $${pass}
	@touch $@
tsample: $(T)sdk1 $(T)sdk2 $(T)sdk3

$(T)tcos: $(T).exists
	@echo $@
	set -x&&\
	icos_bucket_name=$$($(EXE_NOMAN) config preset get misc icos_bucket_name)&&\
	icos_bucket_region=$$($(EXE_NOMAN) config preset get misc icos_bucket_region)&&\
	$(EXE_MAN) cos -N --bucket=$${icos_bucket_name} --region=$${icos_bucket_region} --service-credentials=@json:@file:$(DIR_PRIV)service_creds.json node info
	set -x&&\
	icos_bucket_name=$$($(EXE_NOMAN) config preset get misc icos_bucket_name)&&\
	icos_bucket_endpoint=$$($(EXE_NOMAN) config preset get misc icos_bucket_endpoint)&&\
	icos_bucket_apikey=$$($(EXE_NOMAN) config preset get misc icos_bucket_apikey)&&\
	icos_resource_instance_id=$$($(EXE_NOMAN) config preset get misc icos_resource_instance_id)&&\
	$(EXE_MAN) cos -N --bucket=$${icos_bucket_name} --endpoint=$${icos_bucket_endpoint} --apikey=$${icos_bucket_apikey} --crn=$${icos_resource_instance_id} node info
	$(EXE_MAN) cos node info
	$(EXE_MAN) cos node access_key show self
	$(EXE_MAN) cos node upload $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) cos node download $(CF_LOCAL_SAMPLE_FILENAME) --to-folder=$(DIR_TMP).
	@touch $@
tcos: $(T)tcos
$(T)f5_p1: $(T).exists
	@echo $@
	set -x&&\
	f5_user=$$($(EXE_NOMAN) config preset get tst_faspex5 username)&&\
	f5_meta=$$($(EXE_NOMAN) config preset get misc faspex5_meta)&&\
	$(EXE_MAN) faspex5 package send --value=@json:'{"title":"test title","recipients":[{"name":"'"$${f5_user}"'"}]'"$${f5_meta}"'}' $(CF_LOCAL_SAMPLE_FILEPATH) --ts=@json:'{"content_protection_password":"_content_prot_here_"}'
	@touch $@
$(T)f5_p2: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 package list --value=@json:'{"mailbox":"inbox","state":["released"]}'
	@touch $@
$(T)f5_p3: $(T).exists
	@echo $@
	set -x&&package_id=$$($(EXE_NOMAN) faspex5 pack list --value=@json:'{"mailbox":"inbox","state":["released"],"limit":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 package receive "$${package_id}" --to-folder=$(DIR_TMP).  --ts=@json:'{"content_protection_password":"abc123_yo"}'
	@touch $@
$(T)f5_a1: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 health
	$(EXE_MAN) faspex5 admin res accounts list
	$(EXE_MAN) faspex5 admin res contacts list
	$(EXE_MAN) faspex5 admin res jobs list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res shared_inboxes list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res node list --value=@json:'{"type":"received","subtype":"mypackages"}'
	$(EXE_MAN) faspex5 admin res oauth_clients list
	$(EXE_MAN) faspex5 admin res registrations list
	$(EXE_MAN) faspex5 admin res saml_configs list
	@touch $@

tf5: $(T)f5_p1 $(T)f5_p2 $(T)f5_p3 $(T)f5_a1

tnagios: $(T)fx_nagios $(T)serv_nagios_hsts $(T)serv_nagios_transfer $(T)nd_nagios

$(T)fxgw: $(T).exists
	@echo $@
	$(EXE_MAN) aoc faspex
	@touch $@
