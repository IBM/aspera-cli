##################################
# Integration tests

DIR_TOP=../

include $(DIR_TOP)common.make
include $(SECRETS_FILE_PATH)

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

# setup local environment for preview generation testing
setupprev:
	-sudo asnodeadmin -d -u $$($(EXE_NOMAN) conf id tst_node_preview get username)
	sudo asnodeadmin -a -u $$($(EXE_NOMAN) conf id tst_node_preview get username) -p $$($(EXE_NOMAN) conf id tst_node_preview get password) -x xfer --acl-set admin,impersonation
	sudo asconfigurator -x "user;user_name,xfer;file_restriction,|*;token_encryption_key,$$(base64 < /dev/urandom|head -c32);absolute,AS_NULL"
	sudo asconfigurator -x "server;activity_logging,true;activity_event_logging,true"
	sudo asnodeadmin --reload
	-$(EXE_NOMAN) node -N -Ptst_node_preview access_key delete --id=$$($(EXE_NOMAN) conf id tst_ak_preview get username)
	$(EXE_NOMAN) node -N -Ptst_node_preview access_key create --value=@json:'{"id":"'$$($(EXE_NOMAN) conf id tst_ak_preview get username)'","name":"the test key","secret":"'$$($(EXE_NOMAN) conf id tst_ak_preview get password)'","storage":{"type":"local", "path":"/Users/xfer/docroot"}}'

noderestart:
	sudo launchctl stop com.aspera.asperanoded
	sudo launchctl start com.aspera.asperanoded

# default download folder for Connect Client
DIR_CONNECT_DOWNLOAD=$(HOME)/Desktop
PKG_TEST_TITLE=$(shell date)

# flag files for integration tests generated here
T=$(DIR_TMP)t/

clean::
	rm -fr $(T)
	mkdir $(T)
$(CF_LOCAL_SAMPLE_FILEPATH): $(DIR_TMP).exists
	dd if=/dev/urandom of=$(CF_LOCAL_SAMPLE_FILEPATH) count=1 bs=200k
$(T).exists: $(CF_LOCAL_SAMPLE_FILEPATH)
	mkdir -p $(T)
	touch $@
$(T)unit: $(T).exists
	@echo $@
	set -x;\
	CF_HSTS_SSH_URL=$$($(EXE_NOMAN) conf id tst_server get url) \
	CF_HSTS_SSH_USER=$$($(EXE_NOMAN) conf id tst_server get username) \
	CF_HSTS_SSH_PASS=$$($(EXE_NOMAN) conf id tst_server get password) \
	bundle exec rake spec
	@touch $@
tunit: $(T)unit
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
tshares: $(T)sh1 $(T)sh2

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
	$(EXE_MAN) server upload $(CF_LOCAL_SAMPLE_FILEPATH) --to-folder=$(NEW_SERVER_FOLDER)
	$(EXE_MAN) server upload --src-type=pair $(CF_LOCAL_SAMPLE_FILEPATH) $(NEW_SERVER_FOLDER)/othername
	$(EXE_MAN) server upload --src-type=pair --sources=@json:'["$(CF_LOCAL_SAMPLE_FILEPATH)","$(NEW_SERVER_FOLDER)/othername"]'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"paths":[{"source":"$(CF_LOCAL_SAMPLE_FILEPATH)","destination":"$(NEW_SERVER_FOLDER)/othername"}]}'
	@touch $@
$(T)serv_md5: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server md5sum $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME)
	@touch $@
$(T)serv_down_lcl: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server download $(NEW_SERVER_FOLDER)/$(CF_LOCAL_SAMPLE_FILENAME) --to-folder=$(DIR_TMP).
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
	$(EXE_MAN) -N -Ptst_hstsfaspex_ssh -Plocal_user server nodeadmin -- -l
	@touch $@
$(T)serv_nagios_transfer: $(T).exists
	@echo $@
	$(EXE_MAN) server nagios transfer --to-folder=$(CF_HSTS_FOLDER_UPLOAD) --format=nagios 
	@touch $@
$(T)serv_nagios_webapp: $(T).exists
	@echo $@
	$(EXE_MAN) -N -Ptst_hstsfaspex_ssh -Plocal_user server nagios app_services --format=nagios
	@touch $@
$(T)serv3: $(T).exists
	@echo $@
	$(EXE_MAN) -N -Ptst_hstsfaspex_ssh -Plocal_user server ctl all:status
	@touch $@
$(T)serv_key: $(T).exists
	@echo $@
	$(EXE_MAN) -N -Ptst_server_bykey -Plocal_user server br /
	@touch $@
$(T)asession: $(T).exists
	@echo $@
	remote_host=$$($(EXE_NOMAN) conf id tst_server get url);remote_host=$${remote_host##*/};remote_port="$remote_host";remote_port=$${remote_host#*:};remote_host=$${remote_host%:*};\
	remote_user=$$($(EXE_NOMAN) conf id tst_server get username);\
	remote_pass=$$($(EXE_NOMAN) conf id tst_server get password);\
	$(DIR_BIN)asession @json:'{"remote_host":"'"$${remote_host}"'","remote_user":"'"$${remote_user}"'","ssh_port":'$${remote_port}',"remote_password":"'"$${remote_pass}"'","direction":"receive","destination_root":"$(DIR_TMP).","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@

tfasp: $(T)serv_browse $(T)serv_mkdir $(T)serv_upload $(T)serv_md5 $(T)serv_down_lcl $(T)serv_down_from_node $(T)serv_cp $(T)serv_mv $(T)serv_delete $(T)serv_cleanup1 $(T)serv_info $(T)serv_du $(T)serv_df $(T)asession $(T)serv_nodeadmin $(T)serv_nagios_webapp $(T)serv_nagios_transfer $(T)serv3 $(T)serv_key

$(T)fx_plst: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package list
	@touch $@
$(T)fx_psnd: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package send --delivery-info=@json:'{"title":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)fx_prs: $(T).exists
	@echo $@
	@sleep 5
	pack_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data|tail -n 1);\
	echo "id=$$pack_id";\
	$(EXE_MAN) faspex package recv --box=sent --to-folder=$(DIR_TMP). --id=$$pack_id
	@touch $@
$(T)fx_pri: $(T).exists
	@echo $@
	pack_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data|tail -n 1);\
	echo "id=$$pack_id";\
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --id=$$pack_id
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
	$(EXE_MAN) faspex nagios_check
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
	$(EXE_MAN) console transfer smart sub 112 @json:'{"source":{"paths":["10MB.1"]},"source_type":"user_selected"}'
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
	$(EXE_MAN) node upload --to-folder="$(CF_HSTS_FOLDER_UPLOAD)" --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.1"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:'{"url":"'$${node_url}'","username":"'$${node_user}'","password":"'$${node_pass}'"}'
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
	$(EXE_MAN) node nagios_check
	@touch $@
tnode: $(T)nd1 $(T)nd2 $(T)nd_2_nd_xfer $(T)nd4 $(T)nd5 $(T)nd6 $(T)nd7 $(T)nd_nagios

$(T)aocg1: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud apiinfo
	@touch $@
$(T)aocg2: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud bearer_token --display=data --scope=user:all
	@touch $@
$(T)aocg3: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud organization
	@touch $@
$(T)aocg4: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud workspace
	@touch $@
$(T)aocg5: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud user info show
	@touch $@
$(T)aocg6: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud user info modify @json:'{"name":"dummy change"}'
	@touch $@
taocgen: $(T)aocg1 $(T)aocg2 $(T)aocg3 $(T)aocg4 $(T)aocg5 $(T)aocg6
$(T)aocfbr: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files browse /
	@touch $@
$(T)aocffin: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files find / --value='\.partial$$'
	@touch $@
$(T)aocfmkd: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files mkdir /testfolder
	@touch $@
$(T)aocfren: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files rename /testfolder newname
	@touch $@
$(T)aocfdel: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files delete /newname
	@touch $@
$(T)aocf5: $(T)aocfupl # WS: Demo
	@echo $@
	$(EXE_MAN) oncloud files transfer --workspace=eudemo --from-folder='/ascli_test' --to-folder=/ascli_test2 200KB.1
	@touch $@
$(T)aocfupl: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files upload --to-folder=/ $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocfbearnode: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files bearer /
	@touch $@
$(T)aocfdown: $(T).exists
	@echo $@
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	$(EXE_MAN) oncloud files download --transfer=connect /200KB.1
	@rm -f $(DIR_CONNECT_DOWNLOAD)/200KB.1
	@touch $@
$(T)aocfhttpd: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files http_node_download --to-folder=$(DIR_TMP). /200KB.1
	@touch $@
$(T)aocfv3inf: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files v3 info
	@touch $@
$(T)aocffid: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files file 18891
	@touch $@
$(T)aocfpub: $(T).exists
	@echo $@
	$(EXE_MAN) -N oncloud files browse / --link=$(CF_AOC_PUBLINK_FOLDER)
	$(EXE_MAN) -N oncloud files upload --to-folder=/ $(CF_LOCAL_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_FOLDER)
	@touch $@
$(T)aocshlk1: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files short_link list --value=@json:'{"purpose":"shared_folder_auth_link"}'
	@touch $@
$(T)aocshlk2: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files short_link create --to-folder='ascli test folder link' --value=private
	@touch $@
$(T)aocshlk3: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud files short_link create --to-folder='ascli test folder link' --value=public
	@touch $@
taocf: $(T)aocfbr $(T)aocffin $(T)aocfmkd $(T)aocfren $(T)aocfdel $(T)aocf5 $(T)aocfupl $(T)aocfbearnode $(T)aocfdown $(T)aocfhttpd $(T)aocfv3inf $(T)aocffid $(T)aocfpub $(T)aocshlk1 $(T)aocshlk2 $(T)aocshlk3
$(T)aocp1: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_EMAIL_ADDR)"],"note":"my note"}' $(CF_LOCAL_SAMPLE_FILEPATH)
	$(EXE_MAN) oncloud packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_AOC_EXTERNAL_EMAIL)"]}' --new-user-option=@json:'{"package_contact":true}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)aocp2: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud packages list
	@touch $@
$(T)aocp3: $(T).exists
	@echo $@
	last_pack=$$($(EXE_MAN) oncloud packages list --format=csv --fields=id --display=data|head -n 1);\
	$(EXE_MAN) oncloud packages recv --id=$$last_pack --to-folder=$(DIR_TMP).
	@touch $@
$(T)aocp4: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud packages recv --id=ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345
	@touch $@
$(T)aocp5: $(T).exists
	@echo $@
	set -x;aoc_publink_recv_from_aocuser=$$($(EXE_NOMAN) conf id misc get aoc_publink_recv_from_aocuser);\
	$(EXE_MAN) -N oncloud org --link=$(CF_AOC_PUBLINK_RECV_PACKAGE)
	@touch $@
$(T)aocp6: $(T).exists
	@echo $@
	$(EXE_MAN) -N oncloud packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_DROPBOX)
	@touch $@
$(T)aocp7: $(T).exists
	@echo $@
	$(EXE_MAN) -N oncloud packages send --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'"}' $(CF_LOCAL_SAMPLE_FILEPATH) --link=$(CF_AOC_PUBLINK_SEND_USER)
	@touch $@
$(T)aocp8: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud packages send --workspace="$(CF_AOC_SH_BX_WS)" --value=@json:'{"name":"'"$(PKG_TEST_TITLE)"'","recipients":["$(CF_AOC_SH_BX_NAME)"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@

taocp: $(T)aocp1 $(T)aocp2 $(T)aocp3 $(T)aocp4 $(T)aocp5 $(T)aocp5 $(T)aocp6 $(T)aocp7 $(T)aocp8
$(T)aoc8: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource workspace list
	@touch $@
$(T)aoc9: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 events
	@touch $@
$(T)aoc11: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key create --value=@json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
$(T)aoc12: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v3 access_key delete --id=testsub1
	@touch $@
$(T)aoc9b: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 browse /
	@touch $@
$(T)aoc10: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 mkdir /folder1
	@touch $@
$(T)aoc13: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource node --name=$(CF_AOC_NODE1_NAME) --secret=$(CF_AOC_NODE1_SECRET) v4 delete /folder1
	@touch $@
$(T)aoc14: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
$(T)aoc15: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}'
	@touch $@
taocadm: $(T)aoc8 $(T)aoc9 $(T)aoc9b $(T)aoc10 $(T)aoc11 $(T)aoc12 $(T)aoc13 $(T)aoc14 $(T)aoc15
$(T)aocat4: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats cluster list
	@touch $@
$(T)aocat5: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats cluster clouds
	@touch $@
$(T)aocat6: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats cluster show --cloud=aws --region=eu-west-1 
	@touch $@
$(T)aocat7: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats cluster show --id=1f412ae7-869a-445c-9c05-02ad16813be2
	@touch $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(T)aocat8: $(T).exists
	-$(EXE_MAN) oncloud admin ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
$(T)aocat9: $(T).exists
	@echo $@
	-$(EXE_MAN) oncloud admin ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
	@touch $@
$(T)aocat10: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats access_key list --fields=name,id
	@touch $@
$(T)aocat11: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud admin ats access_key --id=akibmcloud --secret=somesecret node browse /
	@touch $@
$(T)aocat13: $(T).exists
	@echo $@
	-$(EXE_MAN) oncloud admin ats access_key --id=akibmcloud delete
	@touch $@
taocts: $(T)aocat4 $(T)aocat5 $(T)aocat6 $(T)aocat7 $(T)aocat8 $(T)aocat9 $(T)aocat10 $(T)aocat11 $(T)aocat13
$(DIR_TMP)wf_id.txt: $(T)aocauto1
	$(EXE_MAN) oncloud automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data > $@
$(T)aocauto1: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud automation workflow create --value=@json:'{"name":"test_workflow"}'
	@touch $@
$(T)aocauto2: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud automation workflow list
	$(EXE_MAN) oncloud automation workflow list --value=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@touch $@
$(T)aocauto3: $(DIR_TMP)wf_id.txt
	@echo $@
	WF_ID=$$(cat $(DIR_TMP)wf_id.txt);\
	$(EXE_MAN) oncloud automation workflow --id=$$WF_ID action create --value=@json:'{"name":"toto"}' | tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@touch $@
$(T)aocauto10: $(DIR_TMP)wf_id.txt
	@echo $@
	WF_ID=$$(cat $(DIR_TMP)wf_id.txt);\
	$(EXE_MAN) oncloud automation workflow delete --id=$$WF_ID
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
	$(EXE_MAN) ats access_key create --cloud=softlayer --region=$(CF_ICOS_REGION) --params=@json:'{"id":"akibmcloud","secret":"somesecret","name":"my test key","storage":{"type":"ibm-s3","bucket":"$(CF_ICOS_BUCKET)","credentials":{"access_key_id":"$(CF_ICOS_AK_ID)","secret_access_key":"$(CF_ICOS_SECRET_AK)"},"path":"/"}}'
	@touch $@
$(T)at9: $(T).exists
	@echo $@
	-$(EXE_MAN) ats access_key create --cloud=aws --region=$(CF_AWS_REGION) --params=@json:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"'$(CF_AWS_BUCKET)'","credentials":{"access_key_id":"'$(CF_AWS_ACCESS_KEY)'","secret_access_key":"'$(CF_AWS_SECRET_KEY)'"},"path":"/"}}'
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
tcon: $(T)co1 $(T)co2 $(T)co3 $(T)co4 $(T)co5 $(T)co6

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
clean::
	rm -f $(TEST_CONFIG)
$(T)conf_id_1: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name set param value
	@touch $@
$(T)conf_id_2: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name show
	@touch $@
$(T)conf_id_3: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id default set shares conf_name
	@touch $@
$(T)conf_id_4: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name delete
	@touch $@
$(T)conf_id_5: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name initialize @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
$(T)conf_id_6: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config id conf_name update --p1=v1 --p2=v2
	@touch $@
$(T)conf_open: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config open
	@touch $@
$(T)conf_list: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config list
	@touch $@
$(T)conf_over: $(T).exists
	@echo $@
	ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXETESTB) config overview
	@touch $@
$(T)conf_help: $(T).exists
	@echo $@
	$(EXE_MAN) -h
	@touch $@
$(T)conf_open_err: $(T).exists
	@echo $@
	printf -- "---\nconfig:\n  version: 0" > $(TEST_CONFIG)
	-ASCLI_CONFIG_FILE=$(TEST_CONFIG) $(EXE_MAN) config open
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
	$(EXE_MAN) conf wiz --url=https://$(CF_AOC_ORG).ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=$(CF_AOC_USER) --test-mode=yes --use-generic-client=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_wizard_gen: $(T).exists
	@echo $@
	$(EXE_MAN) conf flush_tokens
	$(EXE_MAN) conf wiz --url=https://$(CF_AOC_ORG).ibmaspera.com --config-file=$(SAMPLE_CONFIG_FILE) --pkeypath='' --username=$(CF_AOC_USER) --test-mode=yes
	cat $(SAMPLE_CONFIG_FILE)
	rm -f $(SAMPLE_CONFIG_FILE)
	@touch $@
$(T)conf_genkey: $(T).exists
	@echo $@
	$(EXE_MAN) config genkey $(DIR_TMP)mykey
	@touch $@
$(T)conf_smtp: $(T).exists
	@echo $@
	$(EXE_MAN) config email_test aspera.user1@gmail.com
	@touch $@
$(T)conf_pac: $(T).exists
	@echo $@
	$(EXE_MAN) config proxy_check --fpac=file:///$(DIR_TOP)examples/proxy.pac https://eudemo.asperademo.com
	@touch $@
tconf: $(T)conf_id_1 $(T)conf_id_2 $(T)conf_id_3 $(T)conf_id_4 $(T)conf_id_5 $(T)conf_id_6 $(T)conf_open $(T)conf_list $(T)conf_over $(T)conf_help $(T)conf_open_err $(T)conf_plugins $(T)conf_export $(T)conf_wizard_org $(T)conf_wizard_gen $(T)conf_genkey $(T)conf_smtp $(T)conf_pac

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
	set -x;remote_host=$$($(EXE_NOMAN) conf id tst_server_bykey get url);remote_host=$${remote_host##*/};remote_port="$${remote_host}";remote_port=$${remote_host#*:};remote_host=$${remote_host%:*};\
	remote_user=$$($(EXE_NOMAN) conf id misc get syncuser);\
	local_user_key=$$($(EXE_NOMAN) conf id local_user get ssh_keys);\
	$(EXE_MAN) sync start --parameters=@json:'{"sessions":[{"name":"test","reset":true,"remote_dir":"/sync_test","local_dir":"$(DIR_TMP)contents","host":"'$${remote_host}'","tcp_port":33001,"user":"'$${remote_user}'","private_key_path":"'$${local_user_key}'"}]}'
	@touch $@
tsync: $(T)sync1
$(T)sdk1: $(T).exists
	@echo $@
	tmp=$(DIR_TMP). ruby -I $(DIR_LIB). $(DIR_TOP)examples/transfer.rb
	@touch $@
tsample: $(T)sdk1

$(T)tcos: $(T).exists
	@echo $@
	$(EXE_MAN) -N cos node --bucket=$(CF_ICOS_BUCKET) --service-credentials=@json:@file:$(DIR_PRIV)service_creds.json --region=$(CF_ICOS_REGION) info
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
	$(EXE_MAN) faspex5 package list --value=@json:'{"state":["released"]}'
	@touch $@
$(T)f5_3: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 package send --value=@json:'{"title":"test title","recipients":["admin"]}' $(CF_LOCAL_SAMPLE_FILEPATH)
	@touch $@
$(T)f5_4: $(T).exists
	@echo $@
	package_id=$$($(EXE_NOMAN) faspex5 pack list --value=@json:'{"type":"received","subtype":"mypackages","limit":1}' --fields=id --format=csv --display=data);\
	echo $$package_id;\
	$(EXE_MAN) faspex5 package receive --id=$$package_id --to-folder=$(DIR_TMP).
	@touch $@

tf5: $(T)f5_1 $(T)f5_2 $(T)f5_3 $(T)f5_4


tnagios: $(T)fx_nagios $(T)serv_nagios_webapp $(T)serv_nagios_transfer $(T)nd_nagios

$(T)fxgw: $(T).exists
	@echo $@
	$(EXE_MAN) oncloud faspex
	@touch $@
