##################################
# Integration tests

# root folder is one level up
DIR_TOP=../

include $(DIR_TOP)common.make

all:: tunit tshares tfaspex tconsole tnode taoc tfasp tsync torc tcon tnsync tconf tprev tats tsample tcos tf5
# tshares2 tnagios

# "EXE_MAN" and "EXE_NOMAN" are used to call the tool in the testing environment
# "EXE_MAN" is used to generate sample commands in documentation (see in docs/Makefile)
EXE_MAN=$(EXETESTB) --warnings --config-file=$(TEST_CONF_FILE_PATH)
# "EXE_NOMAN" when the command is not needed in documentation
EXE_NOMAN=$(EXE_MAN)

CF_REMOTE_SAMPLE_FILENAME=200KB.1
CF_LOCAL_SAMPLE_FILENAME=datafile.bin
CF_LOCAL_SAMPLE_FILEPATH=$(DIR_TMP)$(CF_LOCAL_SAMPLE_FILENAME)
CF_HSTS_FOLDER_UPLOAD := $(shell $(EXE_NOMAN) conf id misc get upload_folder)
CF_SHARES_UPLOAD := $(shell $(EXE_NOMAN) conf id misc get shares_upload)
CF_ORCH_WORKFLOW_ID := $(shell $(EXE_NOMAN) conf id misc get orch_workflow_id)
CF_TSTFILE_DCM := $(shell $(EXE_NOMAN) conf id misc get file_dcm)
CF_TSTFILE_PDF := $(shell $(EXE_NOMAN) conf id misc get file_pdf)
CF_TSTFILE_DOCX := $(shell $(EXE_NOMAN) conf id misc get file_docx)
CF_TSTFILE_MXF := $(shell $(EXE_NOMAN) conf id misc get file_mxf)
CF_AOC_NODE1_NAME := $(shell $(EXE_NOMAN) conf id misc get aoc_node1_name)
CF_AOC_NODE1_SECRET := $(shell $(EXE_NOMAN) conf id misc get aoc_node1_secret)
CF_EMAIL_ADDR := $(shell $(EXE_NOMAN) conf id misc get email_internal)
CF_AOC_EXTERNAL_EMAIL := $(shell $(EXE_NOMAN) conf id misc get email_external)
CF_FASPEX_USERNAME := $(shell $(EXE_NOMAN) conf id tst_faspex get username)
CF_HTTP_GW_FQDN := $(shell $(EXE_NOMAN) conf id misc get http_gw_fqdn_port)

# setup local environment on Macos for preview generation testing
setupprev:
	-sudo asnodeadmin -d -u $$($(EXE_NOMAN) conf id tst_node_preview get username)
	sudo asnodeadmin -a -u $$($(EXE_NOMAN) conf id tst_node_preview get username) -p $$($(EXE_NOMAN) conf id tst_node_preview get password) -x xfer --acl-set admin,impersonation
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,$$(base64 < /dev/urandom|head -c32);absolute,AS_NULL"
	sudo asconfigurator -x "server;activity_logging,true;activity_event_logging,true;ssh_port,22"
	-sudo launchctl load  /Library/LaunchDaemons/com.aspera.asperanoded.plist
	if test $$(id -u asperadaemon) -ne $$(stat -f "%u" /Library/Logs/Aspera); then \
	  echo Fixing right;sudo chown asperadaemon: /Library/Logs/Aspera;\
	fi
	sudo launchctl stop com.aspera.asperanoded;sleep 5
	sudo launchctl start com.aspera.asperanoded
	while ! $(EXE_NOMAN) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
	-$(EXE_NOMAN) node -N -Ptst_node_preview access_key delete --id=$$($(EXE_NOMAN) conf id tst_ak_preview get username)
	$(EXE_NOMAN) node -N -Ptst_node_preview access_key create --value=@json:'{"id":"'$$($(EXE_NOMAN) conf id tst_ak_preview get username)'","name":"the test key","secret":"'$$($(EXE_NOMAN) conf id tst_ak_preview get password)'","storage":{"type":"local", "path":"/Users/xfer/docroot"}}'
	rm -f ~/.aspera/$(EXENAME)/persist_store/preview_iteration_transfer_localhost_testkey.txt
noderestart:
	sudo launchctl stop com.aspera.asperanoded
	sudo launchctl start com.aspera.asperanoded

# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
DIR_CONNECT_DOWNLOAD=$(HOME)/Downloads
PKG_TEST_TITLE=Test Pkg $(shell date)

# flag files for integration tests generated here
T=$(DIR_TMP)t/

$(T).exists:
	mkdir -p $(T)
	touch $@
	dd if=/dev/urandom of=$(CF_LOCAL_SAMPLE_FILEPATH) count=10 bs=1m
clean::
	rm -f $(CF_LOCAL_SAMPLE_FILEPATH)
	rm -fr $(T)
	mkdir $(T)
$(T)unit: $(T).exists
	@echo $@
	set -x;\
	CF_HSTS_SSH_URL=$$($(EXE_NOMAN) conf id tst_server get url) \
	CF_HSTS_SSH_USER=$$($(EXE_NOMAN) conf id tst_server get username) \
	CF_HSTS_SSH_PASS=$$($(EXE_NOMAN) conf id tst_server get password) \
	bundle exec rake spec
	@touch $@
tunit: $(T)unit
$(T)shadm: $(T).exists
	@echo $@
	$(EXE_MAN) shares admin share list
	@touch $@
$(T)sh1: $(T).exists
	@echo $@
	$(EXE_MAN) shares repository browse /
	@touch $@
$(T)sh2: $(T).exists
	@echo $@
	$(EXE_MAN) shares repository upload --to-folder=/$(CF_SHARES_UPLOAD) $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) shares repository download --to-folder=$(DIR_TMP). /$(CF_SHARES_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)
	$(EXE_MAN) shares repository delete /$(CF_SHARES_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)sh3: $(T).exists
	@echo $@
	$(EXE_MAN) shares repository upload --to-folder=/$(CF_SHARES_UPLOAD) $(CF_LOCAL_SAMPLE_FILEPATH) --transfer=httpgw --transfer-info=@json:'{"url":"https://$(CF_HTTP_GW_FQDN)/aspera/http-gwy/v1"}'
	$(EXE_MAN) shares repository download --to-folder=$(DIR_TMP). /$(CF_SHARES_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME) --transfer=httpgw --transfer-info=@json:'{"url":"https://$(CF_HTTP_GW_FQDN)/aspera/http-gwy/v1"}'
	$(EXE_MAN) shares repository delete /$(CF_SHARES_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)
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
	set -x;\
	recipient_email=$$($(EXE_NOMAN) conf id misc get email_external);\
	$(EXE_MAN) server upload --src-type=pair $(CF_LOCAL_SAMPLE_FILEPATH) $(NEW_SERVER_FOLDER)/othername --notif-to=$${recipient_email}
	$(EXE_MAN) server upload --src-type=pair --sources=@json:'["$(CF_LOCAL_SAMPLE_FILEPATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CF_LOCAL_SAMPLE_FILEPATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
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
	@touch $@
$(T)serv_key: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_server_bykey -Plocal_user br /
	@touch $@
$(T)asession: $(T).exists
	@echo $@
	remote_host=$$($(EXE_NOMAN) conf id tst_server get url);remote_host=$${remote_host##*/};remote_port="$remote_host";remote_port=$${remote_host#*:};remote_host=$${remote_host%:*};\
	remote_user=$$($(EXE_NOMAN) conf id tst_server get username);\
	remote_pass=$$($(EXE_NOMAN) conf id tst_server get password);\
	$(DIR_BIN)asession @json:'{"remote_host":"'"$${remote_host}"'","remote_user":"'"$${remote_user}"'","ssh_port":'$${remote_port}',"remote_password":"'"$${remote_pass}"'","direction":"receive","destination_root":"$(DIR_TMP).","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@

tfasp: $(T)serv_browse $(T)serv_mkdir $(T)serv_upload $(T)serv_md5 $(T)serv_down_lcl $(T)serv_down_from_node $(T)serv_cp $(T)serv_mv $(T)serv_delete $(T)serv_cleanup1 $(T)serv_info $(T)serv_du $(T)serv_df $(T)asession $(T)serv_nodeadmin $(T)serv_nagios_hsts $(T)serv_nagios_webapp $(T)serv_nagios_transfer $(T)serv3 $(T)serv_key

$(T)fx_plst: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package list
	@touch $@
$(T)fx_psnd: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)","$(CF_FASPEX_USERNAME)"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_prs: $(T)fx_psnd
	@echo $@
	@sleep 5
	set -x;package_id=$$($(EXE_MAN) faspex package list --fields=package_id --format=csv --display=data|tail -n 1);\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --id="$${package_id}"
	set -x;package_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data|tail -n 1);\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --box=sent --id="$${package_id}"
	@touch $@
$(T)fx_pri: $(T).exists
	@echo $@
	set -x;package_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data|tail -n 1);\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --id="$${package_id}"
	@touch $@
$(T)fx_prl: $(T).exists
	@echo $@
	set -x;faspex_publink_recv_from_fxuser=$$($(EXE_NOMAN) conf id misc get faspex_publink_recv_from_fxuser);\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --link="$${faspex_publink_recv_from_fxuser}"
	@touch $@
$(T)fx_prall: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --id=ALL --once-only=yes
	@touch $@
$(T)fx_pslu: $(T).exists
	@echo $@
	set -x;faspex_publink_send_to_fxuser=$$($(EXE_NOMAN) conf id misc get faspex_publink_send_to_fxuser);\
	$(EXE_MAN) faspex package send --link="$${faspex_publink_send_to_fxuser}" --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_psld: $(T).exists
	@echo $@
	set -x;faspex_publink_send_to_dropbox=$$($(EXE_NOMAN) conf id misc get faspex_publink_send_to_dropbox);\
	$(EXE_MAN) faspex package send --link="$${faspex_publink_send_to_dropbox}" --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_storage: $(T).exists
	@echo $@
	$(EXE_MAN) faspex source name "Server Files" node br /
	@touch $@
$(T)fx_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) faspex health
	@touch $@
tfaspex: $(T)fx_plst $(T)fx_psnd $(T)fx_prs $(T)fx_pri $(T)fx_prl $(T)fx_pslu $(T)fx_psld $(T)fx_storage $(T)fx_prall $(T)fx_nagios

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
	set -x;\
	job_id=$$($(EXE_NOMAN) conf id misc get console_smart_id);\
	file_name=$$($(EXE_NOMAN) conf id misc get console_smart_file);\
	$(EXE_MAN) console transfer smart sub $${job_id} @json:'{"source":{"paths":["'"$${file_name}"'"]},"source_type":"user_selected"}'
	@touch $@
tconsole: $(T)cons1 $(T)cons2 $(T)cons3

$(T)nd1: $(T).exists
	@echo $@
	$(EXE_MAN) node info
	$(EXE_MAN) node browse / -r
	$(EXE_MAN) node search / --value=@json:'{"sort":"mtime"}'
	@touch $@
$(T)nd2: $(T).exists
	@echo $@
	$(EXE_MAN) node upload --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --ts=@json:'{"target_rate_cap_kbps":10000}' $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) node download --to-folder=$(DIR_TMP). $(CF_HSTS_FOLDER_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)
	$(EXE_MAN) node delete $(CF_HSTS_FOLDER_UPLOAD)/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)nd_2_nd_xfer: $(T).exists
	@echo $@
	set -x;node_url=$$($(EXE_NOMAN) conf id tst_node get url);\
	node_user=$$($(EXE_NOMAN) conf id tst_node get username);\
	node_pass=$$($(EXE_NOMAN) conf id tst_node get password);\
	$(EXE_MAN) node upload --to-folder="$(CF_HSTS_FOLDER_UPLOAD)" --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"'"$${node_url}"'","username":"'"$${node_user}"'","password":"'"$${node_pass}"'"}'
	$(EXE_MAN) node delete $(CF_HSTS_FOLDER_UPLOAD)/10MB.1
	@touch $@
$(T)nd4: $(T).exists
	@echo $@
	$(EXE_MAN) node service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXE_MAN) node service list
	@echo "waiting a little...";sleep 2
	$(EXE_MAN) node service --id=service1 delete
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
	$(EXE_MAN) node -N -Ptst_node_preview access_key delete --id=aoc_1
	@touch $@
$(T)nd6: $(T).exists
	@echo $@
	$(EXE_MAN) node transfer list --value=@json:'{"active_only":true}'
	@touch $@
$(T)nd7: $(T).exists
	@echo $@
	$(EXE_MAN) node basic_token
	@touch $@
$(T)nd_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) node health
	@touch $@
tnode: $(T)nd1 $(T)nd2 $(T)nd_2_nd_xfer $(T)nd4 $(T)nd5 $(T)nd6 $(T)nd7 $(T)nd_nagios

$(T)aocg1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc -N servers
	set -x;\
	aoc_user_email=$$($(EXE_NOMAN) conf id misc get aoc_user_email);\
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
	$(EXE_MAN) aoc workspace
	@touch $@
$(T)aocg5: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user info show
	@touch $@
$(T)aocg6: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user info modify @json:'{"name":"dummy change"}'
	@touch $@
$(T)aocg7: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user shared_inboxes
	@touch $@
$(T)aocg8: $(T).exists
	@echo $@
	$(EXE_MAN) aoc user workspaces
	@touch $@
taocgen: $(T)aocg1 $(T)aocg2 $(T)aocg3 $(T)aocg4 $(T)aocg5 $(T)aocg6 $(T)aocg7 $(T)aocg8
$(T)aocfbr: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files browse /
	@touch $@
$(T)aocfbt: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files bearer_token_node /
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
	set -x;\
	other_workspace=$$($(EXE_NOMAN) conf id misc get aoc_workspace2);\
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
	set -x;\
	file_id=$$($(EXE_NOMAN) aoc files br /200KB.1 --fields=id --format=csv --display=data);\
	$(EXE_MAN) aoc files file --id=$${file_id} show
	@touch $@
$(T)aocfpub: $(T).exists
	@echo $@
	set -x;\
	aoc_publink_folder=$$($(EXE_NOMAN) conf id misc get aoc_publink_folder);\
	$(EXE_MAN) aoc files browse / -N --link=$${aoc_publink_folder}
	set -x;\
	aoc_publink_folder=$$($(EXE_NOMAN) conf id misc get aoc_publink_folder);\
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
	$(EXE_MAN) aoc packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)"],"note":"my note"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) aoc packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_AOC_EXTERNAL_EMAIL)"]}' --new-user-option=@json:'{"package_contact":true}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocp2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages list
	@touch $@
$(T)aocp3: $(T).exists
	@echo $@
	set -x;package_id=$$($(EXE_NOMAN) aoc packages list --format=csv --fields=id --display=data|head -n 1);\
	$(EXE_MAN) aoc packages recv --id="$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@
$(T)aocp4: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages recv --id=ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345
	@touch $@
$(T)aocp5: $(T).exists
	@echo $@
	set -x;\
	aoc_publink_recv_from_aocuser=$$($(EXE_NOMAN) conf id misc get aoc_publink_recv_from_aocuser);\
	$(EXE_MAN) aoc org -N --link=$${aoc_publink_recv_from_aocuser}
	@touch $@
$(T)aocp6: $(T).exists
	@echo $@
	set -x;\
	aoc_publink_send_shd_inbox=$$($(EXE_NOMAN) conf id misc get aoc_publink_send_shd_inbox);\
	$(EXE_MAN) aoc packages send -N --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$${aoc_publink_send_shd_inbox}
	@touch $@
$(T)aocp7: $(T).exists
	@echo $@
	set -x;\
	aoc_publink_send_aoc_user=$$($(EXE_NOMAN) conf id misc get aoc_publink_send_aoc_user);\
	aoc_publink_send_use_pass=$$($(EXE_NOMAN) conf id misc get aoc_publink_send_use_pass);\
	$(EXE_MAN) aoc packages send -N --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$${aoc_publink_send_aoc_user} --password=$${aoc_publink_send_use_pass}
	@touch $@
$(T)aocp8: $(T).exists
	@echo $@
	set -x;\
	aoc_shbx_ws=$$($(EXE_NOMAN) conf id misc get aoc_shbx_ws);\
	aoc_shbx_name=$$($(EXE_NOMAN) conf id misc get aoc_shbx_name);\
	$(EXE_MAN) aoc packages send --workspace="$${aoc_shbx_ws}" --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["'$${aoc_shbx_name}'"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocp9: $(T).exists
	@echo $@
	set -x;\
	aoc_shbx_ws=$$($(EXE_NOMAN) conf id misc get aoc_shbx_ws);\
	aoc_shbx_name=$$($(EXE_NOMAN) conf id misc get aoc_shbx_name);\
	shbxid=$$($(EXE_NOMAN) aoc user shared_inboxes --select=@json:'{"dropbox.name":"'$${aoc_shbx_name}'"}' --format=csv --fields=dropbox_id --display=data);\
	$(EXE_MAN) aoc packages list --query=@json:'{"dropbox_id":"'$${shbxid}'","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
	@touch $@
taocp: $(T)aocp1 $(T)aocp2 $(T)aocp3 $(T)aocp4 $(T)aocp5 $(T)aocp5 $(T)aocp6 $(T)aocp7 $(T)aocp8 $(T)aocp9
$(T)aoc8: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace list
	@touch $@
$(T)aoc9: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 events
	@touch $@
$(T)aoc11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
$(T)aoc12: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key delete --id=testsub1
	@touch $@
$(T)aoc9b: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 browse /
	@touch $@
$(T)aoc10: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 mkdir /folder1
	@touch $@
$(T)aoc13: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 delete /folder1
	@touch $@
$(T)aoc14: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
$(T)aoc15: $(T).exists
	@echo $@
	set -x;\
	recipient_email=$$($(EXE_NOMAN) conf id misc get email_external);\
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
	$(EXE_MAN) aoc admin res package list
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
	clt_reg_id=$$($(EXE_NOMAN) aoc admin res client_registration_token list --fields=ALL --select=@json:'{"data.name":"test_client_reg1"}' --fields=id --format=csv --display=data);\
	$(EXE_MAN) aoc admin res client_registration_token --id=$${clt_reg_id} delete
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
	$(EXE_MAN) aoc admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(T)aocat8: $(T).exists
	@echo $@
	set -x;\
	icos_bucket_region=$$($(EXE_NOMAN) conf id misc get icos_bucket_region);\
	icos_bucket_name=$$($(EXE_NOMAN) conf id misc get icos_bucket_name);\
	icos_bucket_key=$$($(EXE_NOMAN) conf id misc get icos_bucket_key);\
	icos_bucket_secret=$$($(EXE_NOMAN) conf id misc get icos_bucket_secret);\
	$(EXE_MAN) aoc admin ats access_key create --cloud=softlayer --region=$${icos_bucket_region} --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"'$${icos_bucket_name}'","credentials":{"access_key_id":"'$${icos_bucket_key}'","secret_access_key":"'$${icos_bucket_secret}'"},"path":"/"}}'
	@touch $@
$(T)aocat9: $(T).exists
	@echo $@
	-set -x;\
	aws_bucket_region=$$($(EXE_NOMAN) conf id misc get aws_bucket_region);\
	aws_bucket_name=$$($(EXE_NOMAN) conf id misc get aws_bucket_name);\
	aws_bucket_key=$$($(EXE_NOMAN) conf id misc get aws_bucket_key);\
	aws_bucket_secret=$$($(EXE_NOMAN) conf id misc get aws_bucket_secret);\
	$(EXE_MAN) aoc admin ats access_key create --cloud=aws --region=$${aws_bucket_region} --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'$${aws_bucket_name}'","credentials":{"access_key_id":"'$${aws_bucket_key}'","secret_access_key":"'$${aws_bucket_secret}'"},"path":"/"}}'
	@touch $@
$(T)aocat10: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats access_key list --fields=name,id
	@touch $@
$(T)aocat11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
$(T)aocat13: $(T).exists
	@echo $@
	-$(EXE_MAN) aoc admin ats access_key --id=akibmcloud delete
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
	set -x;wf_id=$$(cat $(DIR_TMP)wf_id.txt);\
	$(EXE_MAN) aoc automation workflow --id="$${wf_id}" action create --value=@json:'{"name":"toto"}' | tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@touch $@
$(T)aocauto10: $(DIR_TMP)wf_id.txt
	@echo $@
	set -x;wf_id=$$(cat $(DIR_TMP)wf_id.txt);\
	$(EXE_MAN) aoc automation workflow delete --id="$${wf_id}"
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
	$(EXE_MAN) orchestrator workflow status
	@touch $@
$(T)o4: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) inputs
	@touch $@
$(T)o5: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) status
	@touch $@
$(T)o6: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) start --params=@json:'{"Param":"world !"}'
	@touch $@
$(T)o7: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow --id=$(CF_ORCH_WORKFLOW_ID) start --params=@json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
	@touch $@
$(T)o8: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator plugins
	@touch $@
$(T)o9: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator processes
	@touch $@

torc: $(T)o1 $(T)o2 $(T)o3 $(T)o4 $(T)o5 $(T)o6 $(T)o7 $(T)o8 $(T)o9

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
	$(EXE_MAN) ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
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
	set -x;\
	icos_bucket_region=$$($(EXE_NOMAN) conf id misc get icos_bucket_region);\
	icos_bucket_name=$$($(EXE_NOMAN) conf id misc get icos_bucket_name);\
	icos_bucket_key=$$($(EXE_NOMAN) conf id misc get icos_bucket_key);\
	icos_bucket_secret=$$($(EXE_NOMAN) conf id misc get icos_bucket_secret);\
	$(EXE_MAN) ats access_key create --cloud=softlayer --region=$${icos_bucket_region} --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"'$${icos_bucket_name}'","credentials":{"access_key_id":"'$${icos_bucket_key}'","secret_access_key":"'$${icos_bucket_secret}'"},"path":"/"}}'
	@touch $@
$(T)at9: $(T).exists
	@echo $@
	-set -x;\
	aws_bucket_region=$$($(EXE_NOMAN) conf id misc get aws_bucket_region);\
	aws_bucket_name=$$($(EXE_NOMAN) conf id misc get aws_bucket_name);\
	aws_bucket_key=$$($(EXE_NOMAN) conf id misc get aws_bucket_key);\
	aws_bucket_secret=$$($(EXE_NOMAN) conf id misc get aws_bucket_secret);\
	$(EXE_MAN) ats access_key create --cloud=aws --region=$${aws_bucket_region} --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'$${aws_bucket_name}'","credentials":{"access_key_id":"'$${aws_bucket_key}'","secret_access_key":"'$${aws_bucket_secret}'"},"path":"/"}}'
	@touch $@
$(T)at10: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key list --fields=name,id
	@touch $@
$(T)at11: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
$(T)at12: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key --id=akibmcloud --secret=somesecret cluster
	@touch $@
$(T)at13: $(T).exists
	$(EXE_MAN) ats access_key --id=akibmcloud delete
	@touch $@
$(T)at14: $(T).exists
	@echo $@
	-$(EXE_MAN) ats access_key --id=ak_aws delete
	@touch $@

tats: $(T)at4 $(T)at5 $(T)at6 $(T)at7 $(T)at2 $(T)at1 $(T)at3 $(T)at8 $(T)at9 $(T)at10 $(T)at11 $(T)at12 $(T)at13 $(T)at14

$(T)co1: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp show
	$(EXE_MAN) config ascp spec
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
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' info
	@touch $@
$(T)co5: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' links list
	@touch $@
$(T)co6: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect id 'Aspera Connect for Windows' links id 'Windows Installer' download --to-folder=$(DIR_TMP).
	@touch $@
$(T)co7: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp info
	@touch $@
$(T)co8: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp install
	@touch $@
tcon: $(T)co1 $(T)co2 $(T)co3 $(T)co4 $(T)co5 $(T)co6 $(T)co7 $(T)co8

$(T)sy1: $(T).exists
	@echo $@
	$(EXE_MAN) node async list
	@touch $@
$(T)sy2: $(T).exists
	@echo $@
	$(EXE_MAN) node async show --id=1
	$(EXE_MAN) node async show --id=ALL
	@touch $@
$(T)sy3: $(T).exists
	@echo $@
	$(EXE_MAN) node async --id=1 counters 
	@touch $@
$(T)sy4: $(T).exists
	@echo $@
	$(EXE_MAN) node async --id=1 bandwidth 
	@touch $@
$(T)sy5: $(T).exists
	@echo $@
	$(EXE_MAN) node async --id=1 files 
	@touch $@
tnsync: $(T)sy1 $(T)sy2 $(T)sy3 $(T)sy4 $(T)sy5

TEST_CONFIG=$(DIR_TMP)sample.conf
EXETESTC=$(EXETESTB) --config-file=$(TEST_CONFIG) 
clean::
	rm -f $(TEST_CONFIG)
$(T)conf_id_1: $(T).exists
	@echo $@
	$(EXETESTC) config id conf_name set param value
	@touch $@
$(T)conf_id_2: $(T).exists
	@echo $@
	$(EXETESTC) config id conf_name show
	@touch $@
$(T)conf_id_3: $(T).exists
	@echo $@
	$(EXETESTC) config id default set shares conf_name
	@touch $@
$(T)conf_id_4: $(T).exists
	@echo $@
	$(EXETESTC) config id conf_name delete
	@touch $@
$(T)conf_id_5: $(T).exists
	@echo $@
	$(EXETESTC) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
$(T)conf_id_6: $(T).exists
	@echo $@
	$(EXETESTC) config id conf_name update --p1=v1 --p2=v2
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
	@touch $@
$(T)conf_help: $(T).exists
	@echo $@
	$(EXE_MAN) -h
	@touch $@
$(T)conf_open_err: $(T).exists
	@echo $@
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-$(EXETESTC) config open
	@touch $@
$(T)conf_plugins: $(T).exists
	@echo $@
	$(EXE_MAN) config plugins
	@touch $@
$(T)conf_export: $(T).exists
	@echo $@
	$(EXE_MAN) config export
	@touch $@
SAMPLE_CONFIG_FILE=$(DIR_TMP)tmp_config.yml
$(T)conf_wizard_org: $(T).exists
	@echo $@
	$(EXE_MAN) conf flush_tokens
	set -x;\
	aoc_org=$$($(EXE_NOMAN) conf id misc get aoc_org);\
	aoc_user_email=$$($(EXE_NOMAN) conf id misc get aoc_user_email);\
	$(EXE_MAN) conf wiz --url=https://$${aoc_org}.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=$${aoc_user_email} --test-mode=yes --use-generic-client=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_wizard_gen: $(T).exists
	@echo $@
	$(EXE_MAN) conf flush_tokens
	set -x;\
	aoc_org=$$($(EXE_NOMAN) conf id misc get aoc_org);\
	aoc_user_email=$$($(EXE_NOMAN) conf id misc get aoc_user_email);\
	$(EXE_MAN) conf wiz --url=https://$${aoc_org}.ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=$${aoc_user_email} --test-mode=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_genkey: $(T).exists
	@echo $@
	$(EXE_MAN) config genkey $(DIR_TMP)mykey
	@touch $@
$(T)conf_smtp: $(T).exists
	@echo $@
	set -x;\
	recipient_email=$$($(EXE_NOMAN) conf id misc get email_external);\
	$(EXE_MAN) config email_test --notif-to=$${recipient_email}
	@touch $@
$(T)conf_pac: $(T).exists
	@echo $@
	$(EXE_MAN) config proxy_check --fpac=file:///$(DIR_TOP)examples/proxy.pac https://eudemo.asperademo.com
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
tconf: $(T)conf_id_1 $(T)conf_id_2 $(T)conf_id_3 $(T)conf_id_4 $(T)conf_id_5 $(T)conf_id_6 $(T)conf_open $(T)conf_list $(T)conf_over $(T)conf_help $(T)conf_open_err $(T)conf_plugins $(T)conf_export $(T)conf_wizard_org $(T)conf_wizard_gen $(T)conf_genkey $(T)conf_smtp $(T)conf_pac $(T)conf_check_gem $(T)conf_doc

$(T)shar2_1: $(T).exists
	@echo $@
	$(EXE_MAN) shares2 appinfo
	@touch $@
$(T)shar2_2: $(T).exists
	@echo $@
	$(EXE_MAN) shares2 userinfo
	@touch $@
$(T)shar2_3: $(T).exists
	@echo $@
	$(EXE_MAN) shares2 repository browse /
	@touch $@
$(T)shar2_4: $(T).exists
	@echo $@
	$(EXE_MAN) shares2 organization list
	@touch $@
$(T)shar2_5: $(T).exists
	@echo $@
	$(EXE_MAN) shares2 project list --organization=Sport
	@touch $@
tshares2: $(T)shar2_1 $(T)shar2_2 $(T)shar2_3 $(T)shar2_4 $(T)shar2_5

$(T)prev_check: $(T).exists
	@echo $@
	$(EXE_MAN) preview check --skip-types=office
	@touch $@
$(T)prev_dcm: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_DCM)" --log-level=debug
	@touch $@
$(T)prev_pdf: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_PDF)" --log-level=debug
	@touch $@
$(T)prev_docx: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_DOCX)" --log-level=debug
	@touch $@
$(T)prev_mxf_blend: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=blend --log-level=debug
	@touch $@
$(T)prev_mxf_png_fix: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_MXF)" --video-png-conv=fixed --log-level=debug
	@touch $@
$(T)prev_mxf_png_ani: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ png "$(CF_TSTFILE_MXF)" --video-png-conv=animated --log-level=debug
	@touch $@
$(T)prev_mxf_reencode: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=reencode --log-level=debug
	@touch $@
$(T)prev_mxf_clips: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --case=$@ mp4 "$(CF_TSTFILE_MXF)" --video-conversion=clips --log-level=debug
	@touch $@
$(T)prev_events: $(T).exists
	@echo $@
	$(EXE_NOMAN) -Ptst_ak_preview node upload "$(CF_TSTFILE_MXF)" "$(CF_TSTFILE_DOCX)" --ts=@json:'{"target_rate_kbps":1000000}'
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
	set -x;\
	remote_host=$$($(EXE_NOMAN) conf id tst_server_bykey get url);\
	remote_host=$${remote_host##*/};\
	remote_port=$${remote_host#*:};\
	remote_host=$${remote_host%:*};\
	remote_user=$$($(EXE_NOMAN) conf id misc get syncuser);\
	local_user_key=$$($(EXE_NOMAN) conf id local_user get ssh_keys);\
	$(EXE_MAN) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"$(DIR_TMP)contents","host":"'"$${remote_host}"'","tcp_port":33001,"user":"'"$${remote_user}"'","private_key_path":"'"$${local_user_key}"'"}]}'
	@touch $@
tsync: $(T)sync1
$(T)sdk1: $(T).exists
	@echo $@
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/transfer.rb
	@touch $@
$(T)sdk2: $(T).exists
	@echo $@
	set -x;url=$$($(EXE_NOMAN) conf id tst_aoc1 get url);\
	user=$$($(EXE_NOMAN) conf id tst_aoc1 get username);\
	keypath=$$($(EXE_NOMAN) conf id tst_aoc1 get private_key);\
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/aoc.rb $${url} $${user} "$${keypath}"
	@touch $@
$(T)sdk3: $(T).exists
	@echo $@
	set -x;url=$$($(EXE_NOMAN) conf id tst_faspex get url);\
	user=$$($(EXE_NOMAN) conf id tst_faspex get username);\
	pass=$$($(EXE_NOMAN) conf id tst_faspex get password);\
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/faspex4.rb $${url} $${user} $${pass}
	@touch $@
tsample: $(T)sdk1 $(T)sdk2 $(T)sdk3

$(T)tcos: $(T).exists
	@echo $@
	set -x;\
	icos_bucket_name=$$($(EXE_NOMAN) conf id misc get icos_bucket_name);\
	icos_bucket_region=$$($(EXE_NOMAN) conf id misc get icos_bucket_region);\
	$(EXE_MAN) cos -N --bucket=$${icos_bucket_name} --region=$${icos_bucket_region} --service-credentials=@json:@file:$(DIR_PRIV)service_creds.json node info
	set -x;\
	icos_bucket_name=$$($(EXE_NOMAN) conf id misc get icos_bucket_name);\
	icos_bucket_endpoint=$$($(EXE_NOMAN) conf id misc get icos_bucket_endpoint);\
	icos_bucket_apikey=$$($(EXE_NOMAN) conf id misc get icos_bucket_apikey);\
	icos_resource_instance_id=$$($(EXE_NOMAN) conf id misc get icos_resource_instance_id);\
	$(EXE_MAN) cos -N --bucket=$${icos_bucket_name} --endpoint=$${icos_bucket_endpoint} --apikey=$${icos_bucket_apikey} --crn=$${icos_resource_instance_id} node info
	$(EXE_MAN) cos node info
	$(EXE_MAN) cos node access_key --id=self show
	$(EXE_MAN) cos node upload $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) cos node download $(CF_LOCAL_SAMPLE_FILENAME) --to-folder=$(DIR_TMP).
	@touch $@
tcos: $(T)tcos

$(T)f5_1: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 node list --value=@json:'{"type":"received","subtype":"mypackages"}'
	@touch $@
$(T)f5_2: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 package list --value=@json:'{"mailbox":"inbox","state":["released"]}'
	@touch $@
$(T)f5_3: $(T).exists
	@echo $@
	set -x;\
	f5_user=$$($(EXE_NOMAN) conf id tst_faspex5 get username);\
	$(EXE_MAN) faspex5 package send --value=@json:'{"title":"test title","recipients":[{"name":"'"$${f5_user}"'"}]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)f5_4: $(T).exists
	@echo $@
	set -x;package_id=$$($(EXE_NOMAN) faspex5 pack list --value=@json:'{"mailbox":"inbox","state":["released"],"limit":1}' --fields=id --format=csv --display=data);\
	$(EXE_MAN) faspex5 package receive --id="$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@

tf5: $(T)f5_1 $(T)f5_2 $(T)f5_3 $(T)f5_4


tnagios: $(T)fx_nagios $(T)serv_nagios_hsts $(T)serv_nagios_transfer $(T)nd_nagios

$(T)fxgw: $(T).exists
	@echo $@
	$(EXE_MAN) aoc faspex
	@touch $@
