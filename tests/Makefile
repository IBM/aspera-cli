##################################
# Integration tests

# root folder is one level up
DIR_TOP=../

include $(DIR_TOP)common.mak

# folder where flag files for integration tests are generated
T=$(DIR_TMP)t/

all:: $(DIR_TOP).gems_checked $(TEST_CONF_FILE_PATH) tunit tshares tfaspex tconsole tnode taoc tserver torc tnsync tnsyncs tconfig tats tcos tf5 tprev
# tnagios: already included

# tests that require user interaction
interactive: $(T)f5_webauth $(T)aoc_webauth $(T)conf_interactive

# all tests, including interactive ones
full: all interactive

# just to test nagios, but those are tested in the respective plugins
only_nagios: $(T)f4_nagios $(T)shares_nagios $(T)cons_nagios $(T)f5_nagios $(T)sadm_nagios_hsts $(T)serv_nagios_transfer $(T)nd_nagios

only_sync: tnsync tnsyncs $(T)serv_sync $(T)aocfsync1 $(T)aocfsync2

only_progress: $(T)serv_upload1 $(T)serv_upload3

# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
DIR_CONNECT_DOWNLOAD=$(HOME)/Downloads/
TIMESTAMP=$(shell LANG=C date)

# temp conf file that is modified, to avoid the test configuration file
TEST_CONFIG=$(DIR_TMP)sample.conf
TMP_CONF=--config-file=$(TEST_CONFIG)
WIZ_TEST=--test-mode=yes
CLI_HOME=$(DIR_PRIV)ascli_home/
# tests use config file in test folder
EXE_COMMON=$(EXETESTB) --home=$(CLI_HOME) --config-file=$(TEST_CONF_FILE_PATH)
# "EXE_MAN" and "EXE_NOMAN" are used to call the tool in the testing environment
# "EXE_MAN" is used to generate sample commands in documentation (see in docs/Makefile)
EXE_MAN=$(EXE_COMMON) --warnings
# "EXE_NOMAN" when the command is not needed in documentation
EXE_NOMAN=$(EXE_COMMON)
# enclose tests that shall result in error
EXE_BEG_ERR=if $(EXE_COMMON)
EXE_SHW_ERR=;then echo "No error: problem";exit 1;else echo "Test ok";fi
EXE_END_ERR=>/dev/null 2>&1$(EXE_SHW_ERR)
# enclose tests that fail, but should not
EXE_BEG_FAI=if $(EXE_COMMON)
EXE_END_FAI=>/dev/null 2>&1;then echo "TODO: test worked, restore test?";else echo "Test known to fail";fi
# enclose tests whose status is ignored, mainly optional cleanups, for restarts
EXE_BEG_IGN=$(EXE_COMMON)
EXE_END_IGN=>/dev/null 2>&1 || true
# simple command line to percent-encode
URL_ENCODER=ruby -r uri -e 'puts URI.encode_www_form_component(ARGV.first)'
# testing file generated locally (special shell characters must be escaped for shell, special makefile characters escaped)
TST_ASC_FILENAME=datafile.bin
TST_ASC_LCL_PATH=$(DIR_TMP)$(TST_ASC_FILENAME)
# This file name contains special characters, it must be quoted when used in shell
TST_UTF_FILENAME=𒐫spécial{\#😀بツ
TST_UTF_LCL_PATH=$(DIR_TMP)$(TST_UTF_FILENAME)
# a medium sized file for testing
TST_MED_FILENAME=$(TST_UTF_FILENAME)
# needs to be quoted, as there is shell special character: "?"
TST_MED_LCL_PATH=faux:///$(shell $(URL_ENCODER) "$(TST_MED_FILENAME)")?100m

# sync dir must be an absolute path
TST_SYNC_LCL_DIR=$(shell realpath "$(DIR_TMP)")/testsync123
ifeq ($(TST_SYNC_LCL_DIR),)
$(error "TST_SYNC_LCL_DIR is empty, see error above")
endif

START_TEST=$(DIR_TOP)tests/mark begin
STOP_TEST=$(DIR_TOP)tests/mark end

# flush cached tokens
clean::
	$(EXE_NOMAN) config flush

###########
# Coverage
clean::
	rm -fr $(DIR_TOP)coverage
	rm -f $(DIR_TOP)simplecov.log

###########
# Tests
# all test cases depend on this
$(T).exists:
	mkdir -p $(T)
	echo 'This is a small test file' > $(TST_ASC_LCL_PATH)
	echo 'This is a small test file' > "$(TST_UTF_LCL_PATH)"
	@$(STOP_TEST) $@
clean::
	rm -f $(TST_ASC_LCL_PATH) "$(TST_UTF_LCL_PATH)"
	rm -fr $(T)
	rm -f $(DIR_TOP).rspec_status
#######################################################################################################################
$(T)unit: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	CF_HSTS_SSH_URL=$$($(EXE_NOMAN) config preset get server_user url) \
	CF_HSTS_SSH_USER=$$($(EXE_NOMAN) config preset get server_user username) \
	CF_HSTS_SSH_PASS=$$($(EXE_NOMAN) config preset get server_user password) \
	bundle exec rake spec
	@$(STOP_TEST) $@
tunit: $(T)unit
#######################################################################################################################
$(T)shares_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares health
	$(EXE_NOMAN) shares health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(T)shares_detect: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config detect @preset:shares_admin.url shares
	@$(STOP_TEST) $@
$(T)shares_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:shares_admin.url shares --username=test --password=test
	@$(STOP_TEST) $@
$(T)shares_admin_1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin node list
	@$(STOP_TEST) $@
$(T)shares_admin_2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin group list
	@$(STOP_TEST) $@
$(T)shares_admin_3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user list
	@$(STOP_TEST) $@
$(T)shares_admin_4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user list --type=local
	@$(STOP_TEST) $@
$(T)shares_admin_5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user app_authorizations 1 show
	@$(STOP_TEST) $@
$(T)shares_admin_6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user app_authorizations 1 modify @json:'{"app_login":true}'
	@$(STOP_TEST) $@
$(T)shares_admin_7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user share_permissions 1 list
	@$(STOP_TEST) $@
$(T)shares_admin_8: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user share_permissions 1 show 1
	@$(STOP_TEST) $@
$(T)shares_admin_9: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin user import --type=saml @json:'{"id":"the_id","name_id":"the_name"}'
	@$(STOP_TEST) $@
$(T)shares_admin_10: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) shares admin user add --type=ldap the_name $(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)shares_admin_11: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin share list --fields=DEF,-status,status_message
	@$(STOP_TEST) $@
$(T)shares_admin_12: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares admin share user_permissions 1 list
	@$(STOP_TEST) $@
$(T)shares_1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares files browse /
	@$(STOP_TEST) $@
$(T)shares_2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares files upload --to-folder=@preset:shares.share1 $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)shares_3: $(T)shares_2
	@$(START_TEST) $@
	$(EXE_MAN) shares files download --to-folder=$(DIR_TMP). @extend:@preset:shares.share1@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)shares_4: $(T)shares_3
	@$(START_TEST) $@
	$(EXE_MAN) shares files delete @extend:@preset:shares.share1@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)shares_5: $(T)shares_4
	@$(START_TEST) $@
	$(EXE_MAN) shares files upload --to-folder=@preset:shares.share1 $(TST_ASC_LCL_PATH) --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy"}'
	@$(STOP_TEST) $@
$(T)shares_6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) shares files upload --to-folder=@preset:shares.share1 'faux:///testfile?1m' --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy","synchronous":true,"api_version":"v1","upload_chunk_size":100000}'
	@$(STOP_TEST) $@
$(T)shares_7: $(T)shares_5
	@$(START_TEST) $@
	$(EXE_MAN) shares files download --to-folder=$(DIR_TMP). @extend:@preset:shares.share1@/$(TST_ASC_FILENAME) --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy"}'
	@$(STOP_TEST) $@
$(T)shares_8: $(T)shares_7
	@$(START_TEST) $@
	$(EXE_MAN) shares files delete @extend:@preset:shares.share1@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
tshares: $(T)shares_nagios $(T)shares_detect $(T)shares_wizard $(T)shares_admin_1 $(T)shares_admin_2 $(T)shares_admin_3 $(T)shares_admin_4 $(T)shares_admin_5 $(T)shares_admin_6 $(T)shares_admin_7 $(T)shares_admin_8 $(T)shares_admin_9 $(T)shares_admin_10 $(T)shares_admin_11 $(T)shares_admin_12 $(T)shares_1 $(T)shares_2 $(T)shares_3 $(T)shares_4 $(T)shares_5 $(T)shares_6 $(T)shares_7 $(T)shares_8
#######################################################################################################################
$(T)serv_browse: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server browse /
	@$(STOP_TEST) $@
$(T)serv_mkdir: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server mkdir @preset:server.inside_folder --logger=stdout
	@$(STOP_TEST) $@
$(T)serv_error: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_ERR) server --password=wrong upload $(TST_ASC_LCL_PATH) --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server --password=wrong browse / --ssh-options=@json:'{"number_of_password_prompts":0}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=foo:// ls .$(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=@preset:node_user.url upload wrong --ts=@json:'{"token":"test"}' --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=@preset:node_user.url upload wrong --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_NOMAN) server -N --url=local:// ls .
	@$(STOP_TEST) $@
$(T)serv_upload1: $(T)serv_mkdir 
	@$(START_TEST) $@
	$(EXE_MAN) server upload '$(TST_MED_LCL_PATH)' --to-folder=@preset:server.inside_folder --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":100000}' --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}' --progressbar=yes
	$(EXE_MAN) server browse @extend:@preset:server.inside_folder@/$(TST_MED_FILENAME)
	@$(STOP_TEST) $@
$(T)serv_upload2: $(T)serv_mkdir 
	@$(START_TEST) $@
	$(EXE_MAN) server upload --src-type=pair '$(TST_MED_LCL_PATH)' @extend:@preset:server.inside_folder@/othername2 --notif-to=@preset:misc.email_external --transfer-info=@json:'{"ascp_args":["-l","100m"]}'
	@$(STOP_TEST) $@
$(T)serv_upload3: $(T)serv_mkdir 
	@$(START_TEST) $@
	$(EXE_MAN) server upload --src-type=pair --sources=@json:@extend:'["$(TST_ASC_LCL_PATH)","@preset:server.inside_folder@/othername3"]' --transfer-info=@json:'{"quiet":false}'  --progress=no
	@$(STOP_TEST) $@
$(T)serv_upload4: $(T)serv_mkdir 
	@$(START_TEST) $@
	$(EXE_MAN) server upload --sources=@ts --ts=@json:@extend:'{"paths":[{"source":"$(TST_ASC_LCL_PATH)","destination":"@preset:server.inside_folder@/othername4"}]}'
	@$(STOP_TEST) $@
$(T)serv_upload5: $(T)serv_mkdir 
	@$(START_TEST) $@
	$(EXE_MAN) server upload --src-type=pair $(TST_ASC_LCL_PATH) @extend:@preset:server.upload_folder@/othername5 --ts=@json:'{"cipher":"aes-192-gcm","content_protection":"encrypt","content_protection_password":"my_secret_here","cookie":"biscuit","create_dir":true,"delete_before_transfer":false,"delete_source":false,"exclude_newer_than":1,"exclude_older_than":10000,"fasp_port":33001,"http_fallback":false,"multi_session":0,"overwrite":"diff+older","precalculate_job_size":true,"preserve_access_time":true,"preserve_creation_time":true,"rate_policy":"fair","resume_policy":"sparse_csum","symlink_policy":"follow"}'
	@$(STOP_TEST) $@
$(T)serv_sync: $(T)serv_upload1 $(T)serv_upload2 $(T)serv_upload3 $(T)serv_upload4 $(T)serv_upload5
	@$(START_TEST) $@
	rm -fr $(TST_SYNC_LCL_DIR)
	mkdir -p $(TST_SYNC_LCL_DIR)
	$(EXE_MAN) server sync start --sync-info=@json:@extend:'{"instance":{"quiet":false},"sessions":[{"name":"mysync","direction":"pull","remote_dir":"@preset:server.inside_folder@","local_dir":"$(TST_SYNC_LCL_DIR)","reset":true}]}'
	$(EXE_MAN) server sync admin status mysync --sync-info=@json:'{"sessions":[{"name":"mysync","local_dir":"$(TST_SYNC_LCL_DIR)"}]}'
	$(EXE_MAN) server sync start --sync-info=@json:@extend:'{"name":"sync2","local":{"path":"$(TST_SYNC_LCL_DIR)"},"remote":{"path":"@preset:server.inside_folder@"},"reset":true,"quiet":false}'
	$(EXE_BEG_FAI) server sync admin status --sync-info=@json:'{"name":"sync2"}' $(EXE_END_FAI)
	$(EXE_MAN) server sync admin status --sync-info=@json:'{"name":"sync2","local":{"path":"$(TST_SYNC_LCL_DIR)"}}'
	@$(STOP_TEST) $@
$(T)serv_upload_ex: $(T)serv_mkdir
	@$(START_TEST) $@
	echo $(TST_ASC_LCL_PATH) > $(DIR_TMP)filelist.txt
	echo $(TST_ASC_LCL_PATH) > $(DIR_TMP)filepairlist.txt
	$(EXE_NOMAN) config echo @extend:@preset:server.inside_folder@/othername --format=text >> $(DIR_TMP)filepairlist.txt
	$(EXE_MAN) server upload --sources=@ts --transfer-info=@json:'{"ascp_args":["--file-list","'"$(DIR_TMP)filelist.txt"'"]}' --to-folder=@preset:server.inside_folder 
	$(EXE_MAN) server upload --sources=@ts --transfer-info=@json:'{"ascp_args":["--file-pair-list","'"$(DIR_TMP)filepairlist.txt"'"]}'
	@$(STOP_TEST) $@
$(T)serv_md5: $(T)serv_upload1
	@$(START_TEST) $@
	$(EXE_MAN) server md5sum @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)serv_down_lcl: $(T)serv_upload1
	@$(START_TEST) $@
	$(EXE_MAN) server download @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME) --to-folder=$(DIR_TMP). --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
	@$(STOP_TEST) $@
$(T)serv_down_from_node: $(T)serv_upload1
	@$(START_TEST) $@
	$(EXE_MAN) server download @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME) --to-folder=@preset:server.upload_folder --transfer=node
	@$(STOP_TEST) $@
$(T)serv_cp: $(T)serv_upload1
	@$(START_TEST) $@
	$(EXE_MAN) server cp @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME) @extend:@preset:server.upload_folder@/200KB.2
	@$(STOP_TEST) $@
$(T)serv_mv: $(T)serv_cp
	@$(START_TEST) $@
	$(EXE_MAN) server mv @extend:@preset:server.upload_folder@/200KB.2 @extend:@preset:server.upload_folder@/to.delete
	@$(STOP_TEST) $@
$(T)serv_delete: $(T)serv_mv
	@$(START_TEST) $@
	$(EXE_MAN) server delete @extend:@preset:server.upload_folder@/to.delete
	@$(STOP_TEST) $@
$(T)serv_cleanup1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server delete @preset:server.inside_folder
	@$(STOP_TEST) $@
$(T)serv_info: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server info
	@$(STOP_TEST) $@
$(T)serv_du: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server du /
	@$(STOP_TEST) $@
$(T)serv_df: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server df
	@$(STOP_TEST) $@
$(T)serv_nagios_transfer: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server health transfer --to-folder=@preset:server.upload_folder --format=nagios 
	$(EXE_BEG_ERR) server health transfer --to-folder=/wrong --format=nagios$(EXE_END_ERR)
	@$(STOP_TEST) $@
$(T)serv_key: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server --preset=server_ssh_key browse /
	@$(STOP_TEST) $@
$(T)asession: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	remote_host=$$($(EXE_NOMAN) config preset get server_user url)&&\
	remote_host=$${remote_host##*/}&&remote_port="$remote_host"&&\
	remote_port=$${remote_host#*:}&&remote_host=$${remote_host%:*}&&\
	$(DIR_BIN)asession @json:@extend:'{"remote_host":"'"$${remote_host}"'","remote_user":"@preset:server_user.username@","ssh_port":'$${remote_port}',"remote_password":"@preset:server_user.password@","direction":"receive","destination_root":"$(DIR_TMP).","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@$(STOP_TEST) $@
$(T)serv_pr1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server upload 'faux:///test1?100m' 'faux:///test2?100m' --to-folder=/Upload --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none","precalculate_job_size":true}' --transfer-info=@json:'{"quiet":false}' --progress=no
	@$(STOP_TEST) $@
$(T)serv_pr2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) server upload 'faux:///test1?100m' 'faux:///test2?100m' --to-folder=/Upload --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none","precalculate_job_size":true}'
	@$(STOP_TEST) $@
tserver: $(T)serv_error $(T)serv_browse $(T)serv_mkdir $(T)serv_upload1 $(T)serv_upload2 $(T)serv_upload3 $(T)serv_upload4 $(T)serv_upload5 $(T)serv_sync $(T)serv_upload_ex $(T)serv_md5 $(T)serv_down_lcl $(T)serv_down_from_node $(T)serv_cp $(T)serv_mv $(T)serv_delete $(T)serv_cleanup1 $(T)serv_info $(T)serv_du $(T)serv_df $(T)asession $(T)serv_nagios_transfer $(T)serv_key
#######################################################################################################################
$(T)f4_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex health
	@$(STOP_TEST) $@
$(T)f4_nagios_fail: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) faspex health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(T)f4_detect: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) config detect @preset:faspex4_user.url
	@$(STOP_TEST) $@
$(T)f4_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:faspex4_user.url faspex --username=test --password=test
	@$(STOP_TEST) $@
$(T)f4_pack_list: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex package list --query=@json:'{"max":5}'
	@$(STOP_TEST) $@
$(T)f4_pack_send: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_internal@","@preset:faspex4_user.username@"]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
	@sleep 8
$(T)f4_prs: $(T)f4_pack_send
	@$(START_TEST) $@
	set -x&&\
	package_id=$$($(EXE_MAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	set -x&&\
	package_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP). --box=sent
	@$(STOP_TEST) $@
$(T)f4_pri: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(T)f4_prl: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) faspex package recv --to-folder=$(DIR_TMP). --link=@preset:faspex4.link_recv_from_user$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)f4_prall: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex package recv ALL --to-folder=$(DIR_TMP). --once-only=yes --query=@json:'{"max":10}'
	@$(STOP_TEST) $@
$(T)f4_pslu: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex package send --link=@preset:faspex4.link_send_to_user --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)f4_psld: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex package send --link=@preset:faspex4.link_send_to_dropbox --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)f4_remote_src: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex source list
	$(EXE_MAN) faspex source info %name:@preset:faspex4.src --storage=@preset:faspex4_storage
	$(EXE_MAN) faspex source node %name:@preset:faspex4.src br / --storage=@preset:faspex4_storage
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"$(TIMESTAMP) package remote","recipients":["@preset:misc.email_internal@"]}' --remote_source=@extend:%name:@preset:faspex4.src sample_source.txt
	@$(STOP_TEST) $@
$(T)f4_misc: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex me
	$(EXE_MAN) faspex address_book
	$(EXE_MAN) faspex login_methods
	@$(STOP_TEST) $@
$(T)f4_v4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=faspex4_admin faspex v4 dropbox list
	$(EXE_MAN) --preset=faspex4_admin faspex v4 dmembership list
	$(EXE_MAN) faspex v4 workgroup list
	$(EXE_MAN) faspex v4 wmembership list
	$(EXE_MAN) faspex v4 user list
	$(EXE_MAN) faspex v4 metadata_profile list
	@$(STOP_TEST) $@
$(T)f4_db1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex dropbox list --recipient=@extend:"*@preset:faspex4.dbx@"
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["*@preset:faspex4.dbx@"]}' $(TST_ASC_LCL_PATH)
	set -x&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient=@extend:"*@preset:faspex4.dbx@" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient=@extend:"*@preset:faspex4.dbx@" --to-folder=$(DIR_TMP).
	$(EXE_MAN) faspex dropbox list --recipient=@extend:"*@preset:faspex4.dbx@"
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["*@preset:faspex4.wkg@"]}' $(TST_ASC_LCL_PATH)
	set -x&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient=@extend:"*@preset:faspex4.wkg@" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient=@extend:"*@preset:faspex4.wkg@" --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
tfaspex: $(T)f4_nagios $(T)f4_nagios_fail $(T)f4_detect $(T)f4_wizard $(T)f4_pack_list $(T)f4_pack_send $(T)f4_prs $(T)f4_pri $(T)f4_pslu $(T)f4_psld $(T)f4_remote_src $(T)f4_prall $(T)f4_misc $(T)f4_v4 $(T)f4_db1 $(T)f4_prl
#######################################################################################################################
$(T)cons_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) console health
	$(EXE_NOMAN) console health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(T)cons_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) config detect @preset:console_admin.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:console_admin.url console --preset=console_admin
	@$(STOP_TEST) $@
$(T)cons1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) console transfer current list
	@$(STOP_TEST) $@
$(T)cons2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) console transfer smart list
	@$(STOP_TEST) $@
$(T)cons3: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) console transfer smart sub @preset:console.smart_id @json:@extend:'{"source":{"paths":["@preset:console.smart_file@"]},"source_type":"user_selected"}'$(EXE_END_FAI)
	@$(STOP_TEST) $@
tconsole: $(T)cons_nagios $(T)cons_wizard $(T)cons1 $(T)cons2 $(T)cons3
$(T)nd_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node health
	$(EXE_NOMAN) node health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(T)nd_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config detect @preset:node_user.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:node_user.url node --username=test --password=test
	@$(STOP_TEST) $@
$(T)nd1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node info --fpac='function FindProxyForURL(url,host){return "DIRECT"}'
	$(EXE_MAN) node license
	$(EXE_MAN) node api_details
	$(EXE_MAN) node browse / -r
	$(EXE_MAN) node search / --query=@json:'{"sort":"mtime"}'
	$(EXE_MAN) node space /
	$(EXE_BEG_IGN) node delete /todelete $(EXE_END_IGN)
	$(EXE_MAN) node mkdir @extend:@preset:server.upload_folder@/todelete
	$(EXE_MAN) node mklink @extend:@preset:server.upload_folder@/todelete @extend:@preset:server.upload_folder@/tdlink
	$(EXE_MAN) node mkfile @extend:@preset:server.upload_folder@/delfile1 "hello world"
	$(EXE_MAN) node rename @preset:server.upload_folder delfile1 delfile
	$(EXE_MAN) node delete @list:@extend:,@preset:server.upload_folder@/todelete,@preset:server.upload_folder@/tdlink,@preset:server.upload_folder@/delfile
	@$(STOP_TEST) $@
$(T)nd2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node upload $(TST_ASC_LCL_PATH) --to-folder=@preset:server.upload_folder --ts=@json:'{"target_rate_cap_kbps":10000}'
	$(EXE_MAN) node download @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	$(EXE_MAN) node delete @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)nd_2_nd_xfer: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node upload --to-folder=@preset:server.upload_folder --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.2"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:@extend:'{"url":"@preset:node_user.url@","username":"@preset:node_user.username@","password":"@preset:node_user.password@"}'
	$(EXE_BEG_IGN) node delete @extend:@preset:server.upload_folder@/10MB.2$(EXE_END_IGN)
	@$(STOP_TEST) $@
$(T)nd4: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) node --preset=node_ak_adm service delete service1$(EXE_END_IGN)
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node --preset=node_ak_adm service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXE_MAN) node --preset=node_ak_adm service list
	@echo "waiting a little...";sleep 2
	$(EXE_MAN) node --preset=node_ak_adm service delete service1
	$(EXE_MAN) node --preset=node_ak_adm service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node --preset=node_ak_adm service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node --preset=node_ak_adm service list
	@$(STOP_TEST) $@
$(T)nd6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node transfer list --query=@json:'{"active_only":true}'
	$(EXE_MAN) node transfer sessions
	@$(STOP_TEST) $@
$(T)nd7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node basic_token
	@$(STOP_TEST) $@
$(T)nd8: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node upload --username=@preset:aoc.ak_name --password=@preset:aoc.ak_secret $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)nd_ak: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node --preset=node_ak_adm access_key list
	@$(STOP_TEST) $@
$(T)nd_ak1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name node_info /
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name browse /
	$(EXE_BEG_ERR)node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @json:'{}'$(EXE_END_ERR)
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder exec:'f["name"].end_with?(".jpg")'
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder @ruby:'->(f){f["name"].end_with?(".jpg")}'
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder
	@$(STOP_TEST) $@
$(T)nd_ak2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name mkdir /folder1
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name rename /folder1 folder2
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete /folder2
	@$(STOP_TEST) $@
$(T)nd_ak3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name upload 'faux:///testfile1?1k' --default_ports=no
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name download testfile1 --to-folder=$(DIR_TMP).
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name show /testfile1
	$(EXE_BEG_ERR) node --preset=node_ak_adm access_key do @preset:aoc.ak_name thumbnail /testfile1$(EXE_END_ERR)
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete testfile1
	@$(STOP_TEST) $@
$(T)nd_ak4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node --preset=node_ak_adm access_key do @preset:aoc.ak_name show %id:1
	@$(STOP_TEST) $@
$(T)nd_ak_bearer: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) node -N --preset=tst_node_preview access_key delete @preset:ak_creds.username$(EXE_END_IGN)
	$(EXE_MAN) node -N --preset=tst_node_preview access_key create @json:@extend:'{"id":"@preset:ak_creds.username@","secret":"@preset:ak_creds.password@","storage":{"type":"local","path":"/"}}'
	sleep 2
	$(EXE_MAN) node -N --preset=tst_node_preview --preset=ak_creds access_key set_bearer_key self @file:@preset:file.private_key
	$(EXE_MAN) node -N --preset=tst_node_preview --preset=ak_creds access_key do self show / --fields=id>$(DIR_TMP)root_id
	$(EXE_MAN) node -N --preset=tst_node_preview --preset=ak_creds access_key do self permission %id:$$(cat $(DIR_TMP)root_id) create @json:'{"access_type":"user","access_id":"666"}'
	$(EXE_MAN) node -N --preset=tst_node_preview --preset=ak_creds bearer_token @file:@preset:file.private_key @json:'{"user_id":"666"}'>$(DIR_TMP)bearer_666
	$(EXE_MAN) node -N --url=@preset:tst_node_preview.url --password="Bearer $$(cat $(DIR_TMP)bearer_666)" --root-id=$$(cat $(DIR_TMP)root_id) access_key do self br /
	$(EXE_MAN) node -N --preset=tst_node_preview access_key delete @preset:ak_creds.username
	@$(STOP_TEST) $@
tndak: $(T)nd_ak $(T)nd_ak1 $(T)nd_ak2 $(T)nd_ak3 $(T)nd_ak4 $(T)nd_ak_bearer
tnode: $(T)nd_wizard $(T)nd_nagios $(T)nd1 $(T)nd2 $(T)nd_2_nd_xfer $(T)nd4 $(T)nd6 $(T)nd7 $(T)nd8 tndak

$(T)aocfxgw: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc gateway --pid-file=$(DIR_TMP)server_pid https://localhost:12345/aspera/faspex & sleep 4
	$(EXE_NOMAN) -N faspex --url=https://localhost:12345/aspera/faspex --username=_unused_ --password=_unused_ --insecure=yes package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway aoc"}' 'faux:///test1?1m'
	kill -INT $$(cat $(DIR_TMP)server_pid)
	@$(STOP_TEST) $@
$(T)aocg1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc -N servers
	$(EXE_MAN) aoc -N remind --username=@preset:aoc.user_email
	@$(STOP_TEST) $@
$(T)aocg2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc bearer_token --display=data --scope=user:all
	@$(STOP_TEST) $@
$(T)aocg3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc organization
	@$(STOP_TEST) $@
$(T)aocg4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc user workspaces list
	@$(STOP_TEST) $@
$(T)aocg5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc user profile show
	@$(STOP_TEST) $@
$(T)aocg6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc user profile modify @json:'{"name":"dummy change"}'
	@$(STOP_TEST) $@
$(T)aocg7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages shared_inboxes list
	@$(STOP_TEST) $@
$(T)aocg8: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc user workspaces current
	@$(STOP_TEST) $@
$(T)aoc_webauth: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) aoc --preset=aoc_web user profile show
	@$(STOP_TEST) $@
taocgen: $(T)aocg1 $(T)aocg2 $(T)aocg3 $(T)aocg4 $(T)aocg5 $(T)aocg6 $(T)aocg7 $(T)aocg8
$(T)aocfbr: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files browse /
	@$(STOP_TEST) $@
$(T)aocfbt: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files bearer_token_node / --cache-tokens=no
	@$(STOP_TEST) $@
$(T)aocffin: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files find / '\.partial$$'
	@$(STOP_TEST) $@
$(T)aoc_tstsrc: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) aoc files delete /testsrc$(EXE_END_IGN)
	$(EXE_MAN) aoc files mkdir /testsrc
	@$(STOP_TEST) $@
$(T)aoc_tstdst: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) aoc files delete /testdst$(EXE_END_IGN)
	$(EXE_NOMAN) aoc files mkdir /somefolder
	$(EXE_MAN) aoc files rename /somefolder testdst
	@$(STOP_TEST) $@
$(T)aocfupl: $(T)aoc_tstsrc
	@$(START_TEST) $@
	$(EXE_MAN) aoc files upload --to-folder=/testsrc $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)aocftr: $(T)aocfupl $(T)aoc_tstdst
	@$(START_TEST) $@
	$(EXE_MAN) aoc files transfer push /testsrc --to-folder=/testdst $(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)aocndinf: $(T)aoc_tstsrc
	@$(START_TEST) $@
	$(EXE_MAN) aoc files node_info /testsrc --format=json --display=data | $(EXE_MAN) aoc files upload --workspace=@preset:aoc.other_workspace --to-folder=@preset:aoc.other_folder $(TST_ASC_FILENAME) --transfer=node --transfer-info=@json:@stdin:
	@$(STOP_TEST) $@
$(T)aocfdel: $(T)aocftr $(T)aocndinf
	@$(START_TEST) $@
	$(EXE_MAN) aoc files delete /testsrc
	@$(STOP_TEST) $@
$(T)aocfbearnode: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files bearer /
	@$(STOP_TEST) $@
$(T)aocfdown: $(T)aoc_tstdst
	@$(START_TEST) $@
	@rm -f $(DIR_CONNECT_DOWNLOAD)$(TST_ASC_FILENAME)
	@-killall asperaconnect
	@sleep 1
	$(EXE_MAN) aoc files download --transfer=connect testdst/$(TST_ASC_FILENAME)
	@rm -f $(DIR_CONNECT_DOWNLOAD)$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)aocfhttpd: $(T)aocftr
	@$(START_TEST) $@
	$(EXE_MAN) aoc files http_node_download --to-folder=$(DIR_TMP). testdst/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(T)aocfv3inf: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files v3 info
	@$(STOP_TEST) $@
$(T)aocfsync1: $(T).exists
	@$(START_TEST) $@
	rm -fr $(TST_SYNC_LCL_DIR)
	mkdir -p $(TST_SYNC_LCL_DIR)
	$(EXE_MAN) aoc files sync start --sync-info=@json:'{"sessions":[{"name":"my_aoc_sync1","direction":"pull","local_dir":"$(TST_SYNC_LCL_DIR)","remote_dir":"/testdst","reset":true}]}'
	$(EXE_MAN) aoc files sync admin status --sync-info=@json:'{"sessions":[{"name":"my_aoc_sync1","direction":"pull","local_dir":"$(TST_SYNC_LCL_DIR)","remote_dir":"/testdst","reset":true}]}'
	@$(STOP_TEST) $@
$(T)aocfsync2: $(T).exists
	@$(START_TEST) $@
	rm -fr $(TST_SYNC_LCL_DIR)
	mkdir -p $(TST_SYNC_LCL_DIR)
	$(EXE_BEG_FAI) aoc files sync start --sync-info=@json:'{"name":"my_aoc_sync2","reset":true,"direction":"pull","local":{"path":"$(TST_SYNC_LCL_DIR)"},"remote":{"path":"/testdst"}}'$(EXE_END_FAI)
	$(EXE_BEG_FAI) aoc files sync admin status --sync-info=@json:'{"name":"my_aoc_sync2","reset":true,"direction":"pull","local":{"path":"$(TST_SYNC_LCL_DIR)"},"remote":{"path":"/testdst"}}'$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)aocffid: $(T)aocftr
	@$(START_TEST) $@
	set -x&&\
	file_id=$$($(EXE_NOMAN) aoc files br testdst/$(TST_ASC_FILENAME) --fields=id --format=csv --display=data)&&\
		$(EXE_MAN) aoc files show %id:$${file_id}
	$(EXE_MAN) aoc files show /
	$(EXE_MAN) aoc files show testdst/$(TST_ASC_FILENAME)
	$(EXE_BEG_IGN) aoc files mkdir @preset:aoc.test_folder$(EXE_END_IGN)
	$(EXE_NOMAN) aoc files upload --to-folder=@preset:aoc.test_folder --src-type=pair @preset:file.mpg video_file.mpg
	$(EXE_NOMAN) aoc files upload --to-folder=@preset:aoc.test_folder --src-type=pair @preset:file.jpg image_file.mpg
	$(EXE_MAN) aoc files permission @preset:aoc.test_folder list
	$(EXE_MAN) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg
	$(EXE_MAN) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg --query=@json:'{"text":true,"double":true}'
	$(EXE_NOMAN) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg --query=@json:'{"text":true,"double":false}'
	env -u TERM_PROGRAM -u LC_TERMINAL $(EXE_NOMAN) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg
	@$(STOP_TEST) $@
#	$(EXE_MAN) aoc files modify @preset:aoc.test_folder
$(T)aocfpub: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files browse / -N --url=@preset:aoc.publink_folder_nopass
	$(EXE_MAN) aoc files browse / -N --url=@preset:aoc.publink_folder_pass --password=@preset:aoc.publink_password
	$(EXE_MAN) aoc files upload --to-folder=/ $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.publink_folder_nopass
	@$(STOP_TEST) $@
$(T)aoc_lnk_priv: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files browse / --url=@preset:aoc.privlink
	@$(STOP_TEST) $@
$(T)aocshlk2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files short_link private create /testdst
	@$(STOP_TEST) $@
$(T)aocshlk3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc files short_link public create testdst
	@$(STOP_TEST) $@
$(T)aocshlk1: $(T)aocshlk2 $(T)aocshlk3
	@$(START_TEST) $@
	$(EXE_MAN) aoc files short_link private list /testdst
	@$(STOP_TEST) $@
taocf: $(T)aocfbr $(T)aocfbt $(T)aocffin $(T)aoc_tstsrc $(T)aoc_tstdst $(T)aocfupl $(T)aocftr $(T)aocndinf $(T)aocfdel $(T)aocfbearnode $(T)aocfdown $(T)aocfhttpd $(T)aocfv3inf $(T)aocfsync1 $(T)aocfsync2 $(T)aocffid $(T)aocfpub $(T)aoc_lnk_priv $(T)aocshlk1 $(T)aocshlk2 $(T)aocshlk3 $(T)aocfxgw
$(T)aocp1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_internal@"],"note":"my note"}' $(TST_ASC_LCL_PATH)
	$(EXE_MAN) aoc packages send @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_external@"]}' --new-user-option=@json:'{"package_contact":true}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)aocp2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages list
	@$(STOP_TEST) $@
$(T)aocp3: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) aoc packages list --format=csv --fields=id --display=data|head -n 1)&&\
	$(EXE_MAN) aoc packages recv "$${package_id}" --to-folder=$(DIR_TMP).&&\
	$(EXE_MAN) aoc packages browse "$${package_id}" /contents
	@$(STOP_TEST) $@
$(T)aocp4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages recv ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345
	@$(STOP_TEST) $@
$(T)aocp5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc org -N --url=@preset:aoc.publink_recv_from_aocuser
	@$(STOP_TEST) $@
$(T)aocp_send_pub_sh: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send @json:'{"name":"Test Package $(TIMESTAMP)"}' $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.publink_send_shd_inbox
	@$(STOP_TEST) $@
$(T)aocp_send_pub_usr: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send @json:'{"name":"Test Package $(TIMESTAMP)"}' $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.publink_send_aoc_user --password=@preset:aoc.publink_send_use_pass
	@$(STOP_TEST) $@
$(T)aocp_send_shbx: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send --workspace=@preset:aoc.shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:aoc.shbx_name@"]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)aocp_send_sh_meta_long: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send --workspace=@preset:aoc.shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:aoc.shbx_name@"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)aocp_send_sh_meta_short: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages send --workspace=@preset:aoc.shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:aoc.shbx_name@"],"metadata":{"Project Id":"456","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)aocp_recv_shbx: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages recv ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345 --query=@json:@extend:'{"dropbox_name":"@preset:aoc.shbx_name@","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false}' --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000}'
	@$(STOP_TEST) $@
$(T)aocp_list_shbx: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc packages list --query=@json:@extend:'{"dropbox_name":"@preset:aoc.shbx_name@","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
	@$(STOP_TEST) $@
taocp: $(T)aocp1 $(T)aocp2 $(T)aocp3 $(T)aocp4 $(T)aocp5 $(T)aocp5 $(T)aocp_send_pub_sh $(T)aocp_send_pub_usr $(T)aocp_send_shbx $(T)aocp_send_sh_meta_long $(T)aocp_send_sh_meta_short $(T)aocp_recv_shbx $(T)aocp_list_shbx
$(T)aocadm1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin auth_providers list
	$(EXE_BEG_FAI) aoc admin subscription$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)aoc8: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource workspace list
	@$(STOP_TEST) $@
$(T)aoc9: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret v3 events
	@$(STOP_TEST) $@
$(T)aoc11: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret v3 access_key create @json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@$(STOP_TEST) $@
$(T)aoc12: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret v3 access_key delete testsub1
	@$(STOP_TEST) $@
$(T)aoc9b: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret browse /
	@$(STOP_TEST) $@
$(T)aoc10: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret mkdir /folder1
	@$(STOP_TEST) $@
$(T)aoc13: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource node do %name:@preset:aoc.ak_name --secret=@preset:aoc.ak_secret delete /folder1
	@$(STOP_TEST) $@
$(T)aoc14: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@$(STOP_TEST) $@
$(T)aoc15: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin analytics transfers organization --query=@json:'{"status":"completed","direction":"receive"}' --notif-to=@preset:misc.email_external --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
	@$(STOP_TEST) $@
$(T)aocarself: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin res self show
	$(EXE_MAN) --preset=aoc_admin aoc admin res organization show
	$(EXE_MAN) --preset=aoc_admin aoc admin res user list
	$(EXE_MAN) --preset=aoc_admin aoc admin res user modify @extend:%name:@preset:aoc.user_email@ @json:'{"deactivated":false}'
	$(EXE_MAN) --preset=aoc_admin aoc admin res group list
	$(EXE_MAN) --preset=aoc_admin aoc admin res client list
	$(EXE_MAN) --preset=aoc_admin aoc admin res contact list
	$(EXE_MAN) --preset=aoc_admin aoc admin res dropbox list
	$(EXE_MAN) --preset=aoc_admin aoc admin res node list
	$(EXE_MAN) --preset=aoc_admin aoc admin res operation list
	$(EXE_MAN) --preset=aoc_admin aoc admin res package list --http-options=@json:'{"read_timeout":120.0}'
	$(EXE_MAN) --preset=aoc_admin aoc admin res saml_configuration list
	$(EXE_MAN) --preset=aoc_admin aoc admin res dropbox_membership list
	$(EXE_MAN) --preset=aoc_admin aoc admin res workspace_membership list
	$(EXE_MAN) --preset=aoc_admin aoc admin res short_link list
	$(EXE_MAN) --preset=aoc_admin aoc admin res application list
	$(EXE_MAN) --preset=aoc_admin aoc admin res client_access_key list
	$(EXE_MAN) --preset=aoc_admin aoc admin res kms_profile list
	@$(STOP_TEST) $@
$(T)aoccltreg: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin res client_registration_token create @json:'{"data":{"name":"test_client_reg1","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}'
	$(EXE_MAN) --preset=aoc_admin aoc admin res client_registration_token list
	set -x&&\
	clt_reg_id=$$($(EXE_NOMAN) --preset=aoc_admin aoc admin res client_registration_token list --fields=ALL --select=@json:'{"data.name":"test_client_reg1"}' --fields=id --format=csv --display=data|tail -n 1)&&\
	$(EXE_MAN) --preset=aoc_admin aoc admin res client_registration_token delete $${clt_reg_id}
	@$(STOP_TEST) $@
taocadm: $(T)aocadm1 $(T)aoc8 $(T)aoc9 $(T)aoc9b $(T)aoc10 $(T)aoc11 $(T)aoc12 $(T)aoc13 $(T)aoc14 $(T)aoc15 $(T)aocarself $(T)aoccltreg
$(T)aocat4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc admin ats cluster list
	@$(STOP_TEST) $@
$(T)aocat5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc admin ats cluster clouds
	@$(STOP_TEST) $@
$(T)aocat6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc admin ats cluster show --cloud=aws --region=eu-west-1
	@$(STOP_TEST) $@
$(T)aocat7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) aoc admin ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@$(STOP_TEST) $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(T)aocat8: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) --preset=aoc_admin aoc admin ats access_key delete ak1ibmcloud$(EXE_END_IGN)
	$(EXE_BEG_FAI) --preset=aoc_admin aoc admin ats access_key create --cloud=softlayer --region=@preset:icos.bucket_region --params=@json:@extend:'{"id":"ak1ibmcloud","secret":"my_secret_here","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:icos.bucket_name@","credentials":{"access_key_id":"@preset:icos.bucket_key@","secret_access_key":"@preset:icos.bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)aocat9: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) --preset=aoc_admin aoc admin ats access_key create --cloud=aws --region=@preset:aws.bucket_region --params=@json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:aws.bucket_name@","credentials":{"access_key_id":"@preset:aws.bucket_key@","secret_access_key":"@preset:aws.bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)aocat10: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) --preset=aoc_admin aoc admin ats access_key list --fields=name,id$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)aocat11: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc admin ats access_key node ak1ibmcloud --secret=my_secret_here browse /
	@$(STOP_TEST) $@
$(T)aocat13: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) --preset=aoc_admin aoc admin ats access_key delete ak1ibmcloud$(EXE_END_FAI)
	@$(STOP_TEST) $@
taocts: $(T)aocat4 $(T)aocat5 $(T)aocat6 $(T)aocat7 $(T)aocat8 $(T)aocat9 $(T)aocat10 $(T)aocat11 $(T)aocat13
$(DIR_TMP)wf_id: $(T)aocauto1
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data>$@
$(T)aocauto1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow create @json:'{"name":"test_workflow"}'
	@$(STOP_TEST) $@
$(T)aocauto2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow list
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow list --query=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@$(STOP_TEST) $@
$(T)aocauto3: $(DIR_TMP)wf_id
	@$(START_TEST) $@
	set -x&&\
	wf_id=$$(cat $(DIR_TMP)wf_id)&&\
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow action $${wf_id} create @json:'{"name":"toto"}' \
		| tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@$(STOP_TEST) $@
$(T)aocauto10: $(DIR_TMP)wf_id
	@$(START_TEST) $@
	set -x&&\
	wf_id=$$(cat $(DIR_TMP)wf_id)&&\
	$(EXE_MAN) --preset=aoc_admin aoc automation workflow delete $${wf_id}
	rm -f $(T)wf.id
	@$(STOP_TEST) $@
taocauto: $(T)aocauto1 $(T)aocauto2 $(T)aocauto3 $(T)aocauto10
taoc: taocgen taocf taocp taocadm taocts taocauto

$(T)orch_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) config detect @preset:orch_user.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:orch_user.url orchestrator --username=test --password=test
	@$(STOP_TEST) $@
$(T)orch_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator health
	$(EXE_BEG_ERR) orchestrator health --url=https://wrong.url --format=nagios$(EXE_END_ERR)
	@$(STOP_TEST) $@
$(T)o2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator info
	$(EXE_MAN) orchestrator workflow list
	@$(STOP_TEST) $@
$(T)o3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow status ALL
	@$(STOP_TEST) $@
$(T)o4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow inputs @preset:orch.workflow_id
	@$(STOP_TEST) $@
$(T)o5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow status @preset:orch.workflow_id
	@$(STOP_TEST) $@
$(T)o6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow start @preset:orch.workflow_id @json:'{"Param":"world !"}'
	@$(STOP_TEST) $@
$(T)o7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow start @preset:orch.workflow_id @json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
	@$(STOP_TEST) $@
$(T)o8: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator plugins
	@$(STOP_TEST) $@
$(T)o9: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator processes
	@$(STOP_TEST) $@
$(T)o10: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) orchestrator workflow details @preset:orch.workflow_id
	$(EXE_MAN) orchestrator workflow export @preset:orch.workflow_id
	@$(STOP_TEST) $@

torc: $(T)orch_wizard $(T)orch_nagios $(T)o2 $(T)o3 $(T)o4 $(T)o5 $(T)o6 $(T)o7 $(T)o8 $(T)o9 $(T)o10

$(T)at4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats cluster list
	@$(STOP_TEST) $@
$(T)at5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats cluster clouds
	@$(STOP_TEST) $@
$(T)at6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats cluster show --cloud=aws --region=eu-west-1
	@$(STOP_TEST) $@
$(T)at7: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@$(STOP_TEST) $@
$(T)at2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats api_key instances
	@$(STOP_TEST) $@
$(T)at1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats api_key list
	@$(STOP_TEST) $@
$(T)at3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats api_key create
	@$(STOP_TEST) $@
$(T)at8: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_IGN) ats access_key delete ak2ibmcloud$(EXE_END_IGN)
	$(EXE_BEG_FAI) ats access_key create --cloud=softlayer --region=@preset:icos.bucket_region --params=@json:@extend:'{"id":"ak2ibmcloud","secret":"my_secret_here","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:icos.bucket_name@","credentials":{"access_key_id":"@preset:icos.bucket_key@","secret_access_key":"@preset:icos.bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	$(EXE_MAN) ats access_key entitlement ak2ibmcloud
	$(EXE_MAN) ats access_key show ak2ibmcloud
	@$(STOP_TEST) $@
$(T)at9: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) ats access_key create --cloud=aws --region=@preset:aws.bucket_region --params=@json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:aws.bucket_name@","credentials":{"access_key_id":"@preset:aws.bucket_key@","secret_access_key":"@preset:aws.bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)at10: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) ats access_key list --fields=name,id$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)at11: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats access_key node ak2ibmcloud browse / --secret=my_secret_here
	@$(STOP_TEST) $@
$(T)at12: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) ats access_key cluster ak2ibmcloud --secret=my_secret_here
	@$(STOP_TEST) $@
$(T)at13: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) ats access_key delete ak2ibmcloud$(EXE_END_FAI)
	@$(STOP_TEST) $@
$(T)at14: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_FAI) ats access_key delete ak_aws$(EXE_END_FAI)
	@$(STOP_TEST) $@

tats: $(T)at4 $(T)at5 $(T)at6 $(T)at7 $(T)at2 $(T)at1 $(T)at3 $(T)at8 $(T)at9 $(T)at10 $(T)at11 $(T)at12 $(T)at13 $(T)at14

$(T)sy1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node async list
	@$(STOP_TEST) $@
$(T)sy2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node async show 1
	$(EXE_MAN) node async show ALL
	@$(STOP_TEST) $@
$(T)sy3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node async counters 1
	@$(STOP_TEST) $@
$(T)sy4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node async bandwidth 1
	@$(STOP_TEST) $@
$(T)sy5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) node async files 1
	@$(STOP_TEST) $@
$(T)ndsyncv1: $(T).exists
	@$(START_TEST) $@
	rm -fr $(TST_SYNC_LCL_DIR)
	mkdir -p $(TST_SYNC_LCL_DIR)
	$(EXE_MAN) node sync start --sync-info=@json:'{"sessions":[{"name":"my_node_sync1","direction":"pull","local_dir":"$(TST_SYNC_LCL_DIR)","remote_dir":"/aspera-test-dir-tiny","reset":true}]}'
	$(EXE_MAN) node sync admin status --sync-info=@json:'{"sessions":[{"name":"my_node_sync1","direction":"pull","local_dir":"$(TST_SYNC_LCL_DIR)","remote_dir":"/aspera-test-dir-tiny","reset":true}]}'
	@$(STOP_TEST) $@
$(T)ndsyncv2: $(T).exists
	@$(START_TEST) $@
	rm -fr $(TST_SYNC_LCL_DIR)
	mkdir -p $(TST_SYNC_LCL_DIR)
	$(EXE_MAN) node sync start --sync-info=@json:'{"name":"my_node_sync2","reset":true,"direction":"pull","local":{"path":"$(TST_SYNC_LCL_DIR)"},"remote":{"path":"/aspera-test-dir-tiny"}}'
	$(EXE_MAN) node sync admin status --sync-info=@json:'{"name":"my_node_sync2","reset":true,"direction":"pull","local":{"path":"$(TST_SYNC_LCL_DIR)"},"remote":{"path":"/aspera-test-dir-tiny"}}'
	@$(STOP_TEST) $@
tnsync: $(T)sy1 $(T)sy2 $(T)sy3 $(T)sy4 $(T)sy5 $(T)ndsyncv1 $(T)ndsyncv2

$(T)sync_create: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	hostport=$$($(EXE_NOMAN) config preset get server_user url|cut -f3 -d/)&&\
	host=$${hostport%:*}&&\
	port=$${hostport#*:}&&\
	$(EXE_MAN) node ssync create @json:@extend:'{"configuration":{"name":"my_node_sync","local":{"path":"@preset:sync.local_path@"},"remote":{"host":"'"$${host}"'","port":'"$${port}"',"user":"@preset:server_user.username@","pass":"@preset:server_user.password@","path":"@preset:sync.remote_path@"}}}'
	$(EXE_MAN) node ssync list
	@$(STOP_TEST) $@
$(T)sync_other: $(T)sync_create
	@$(START_TEST) $@
	$(EXE_MAN) node ssync start %name:my_node_sync
	$(EXE_MAN) node ssync show %name:my_node_sync
	$(EXE_MAN) node ssync bandwidth %name:my_node_sync
	$(EXE_MAN) node ssync counters %name:my_node_sync
	$(EXE_MAN) node ssync files %name:my_node_sync
	$(EXE_MAN) node ssync state %name:my_node_sync
	$(EXE_MAN) node ssync stop %name:my_node_sync
	$(EXE_MAN) node ssync summary %name:my_node_sync
	$(EXE_MAN) node ssync delete %name:my_node_sync
	@$(STOP_TEST) $@
tnsyncs: $(T)sync_create $(T)sync_other

clean::
	rm -f $(TEST_CONFIG)

$(T)conf_ascp_1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp show
	$(EXE_MAN) config ascp spec
	$(EXE_MAN) config ascp errors
	@$(STOP_TEST) $@
$(T)conf_ascp_2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp products list
	$(EXE_MAN) $(TMP_CONF) config ascp products use 'Aspera Connect'
	$(EXE_MAN) $(TMP_CONF) config ascp use /usr/bin/ascp
	@$(STOP_TEST) $@
$(T)conf_ascp_3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp connect list
	@$(STOP_TEST) $@
$(T)conf_ascp_4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp connect info 'Aspera Connect for Windows'
	@$(STOP_TEST) $@
$(T)conf_ascp_5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' list
	@$(STOP_TEST) $@
$(T)conf_ascp_6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' download 'Windows Installer' --to-folder=$(DIR_TMP).
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' open documentation
	@$(STOP_TEST) $@
$(T)conf_ascp_7: $(T).exists
	@$(START_TEST) $@
	rm -fr "$$($(EXE_NOMAN) --show-config --fields=sdk_folder)"
	$(EXE_MAN) config ascp install
	rm -fr $(DIR_TMP)sdk_test_dir
	$(EXE_MAN) config ascp install --sdk-folder=$(DIR_TMP)sdk_test_dir
	@$(STOP_TEST) $@
$(T)conf_ascp_8: $(T)conf_ascp_7
	@$(START_TEST) $@
	$(EXE_MAN) config ascp info --sdk-folder=$(DIR_TMP)sdk_test_dir
	@$(STOP_TEST) $@
$(T)conf_pset_1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset set conf_name param value
	$(EXE_MAN) $(TMP_CONF) config preset unset conf_name param
	$(EXE_NOMAN) config preset lookup --url=@preset:faspex4_user.url --username=@preset:faspex4_user.username
	@$(STOP_TEST) $@
$(T)conf_pset_2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset show conf_name
	@$(STOP_TEST) $@
$(T)conf_pset_3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset set default shares conf_name
	@$(STOP_TEST) $@
$(T)conf_pset_4: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset delete conf_name
	@$(STOP_TEST) $@
$(T)conf_pset_5: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset initialize conf_name @json:'{"p1":"v1","p2":"v2"}'
	@$(STOP_TEST) $@
$(T)conf_pset_6: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset update conf_name --p1=v1 --p2=v2
	@$(STOP_TEST) $@
$(T)conf_open: $(T).exists
	@$(START_TEST) $@
	@echo $@ open configuration file in text editor
	$(EXE_MAN) $(TMP_CONF) config open
	@$(STOP_TEST) $@
$(T)conf_list: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset list
	@$(STOP_TEST) $@
$(T)conf_over: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) $(TMP_CONF) config preset overview
	@$(STOP_TEST) $@
$(T)conf_gem: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config gem path
	$(EXE_MAN) config gem version
	$(EXE_MAN) config gem name
	$(EXE_MAN) config folder
	$(EXE_MAN) $(TMP_CONF) config initdemo
	$(EXE_NOMAN) $(TMP_CONF) config initdemo
	@$(STOP_TEST) $@
$(T)conf_vault: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	vault_file=$$(cd $(DIR_TMP);pwd -P)/sample_vault.bin&&\
	rm -f $$vault_file&&\
	$(EXE_NOMAN) $(TMP_CONF) config preset set GLOBAL vault @json:'{"type":"file","name":"'"$${vault_file}"'"}'
	$(EXE_NOMAN) $(TMP_CONF) config preset set GLOBAL vault_password _simple_one_
	$(EXE_MAN) $(TMP_CONF) config vault create mylabel @json:'{"password":"my_password_here","description":"my secret"}'
	$(EXE_MAN) $(TMP_CONF) config vault list
	$(EXE_MAN) $(TMP_CONF) config vault show mylabel
	$(EXE_NOMAN) $(TMP_CONF) config preset ask mypreset <<< $$'username\npassword\n\ntheuser\nthepass\n'
	$(EXE_NOMAN) $(TMP_CONF) config preset secure mypreset
	new_pass=_other_one_&&\
	$(EXE_NOMAN) $(TMP_CONF) config vault password $${new_pass}&&\
	$(EXE_NOMAN) $(TMP_CONF) config preset set GLOBAL vault_password $${new_pass}
	$(EXE_MAN) $(TMP_CONF) config vault list
	$(EXE_MAN) $(TMP_CONF) config vault delete mylabel
	$(EXE_MAN) $(TMP_CONF) config echo @vault:mypreset.password
	$(EXE_BEG_ERR)$(TMP_CONF) config echo @vault:bad$(EXE_END_ERR)
	$(EXE_BEG_ERR)$(TMP_CONF) config echo @vault:bad.password$(EXE_END_ERR)
	$(EXE_BEG_ERR)$(TMP_CONF) config echo @vault:mypreset.bad$(EXE_END_ERR)
	@$(STOP_TEST) $@
$(T)conf_help: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) -h
	$(EXE_NOMAN) --bash-comp
	$(EXE_MAN) config coffee
	$(EXE_MAN) config coffee --ui=text
	env -u TERM_PROGRAM -u LC_TERMINAL $(EXE_NOMAN) config coffee --ui=text
	@$(STOP_TEST) $@
$(T)conf_plugins: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config plugin list
	$(EXE_MAN) config plugin create mycommand $(DIR_TMP)
	$(EXE_NOMAN) mycommand --plugin-folder=$(DIR_TMP)
	@$(STOP_TEST) $@
$(T)conf_wizard_org: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config flush_tokens
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:aoc.org aoc --pkeypath= --username=@preset:aoc.user_email --use-generic-client=yes
	@$(STOP_TEST) $@
$(T)conf_wizard_gen: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config flush_tokens
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:aoc.org aoc --pkeypath= --username=@preset:aoc.user_email
	@$(STOP_TEST) $@
$(T)conf_detect: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config detect @preset:aoc.org aoc
	$(EXE_MAN) config detect @preset:faspex4_user.url
	$(EXE_MAN) config detect @preset:node_user.url
	@$(STOP_TEST) $@
$(T)conf_genkey: $(T).exists
	@$(START_TEST) $@
	rm -f $(DIR_TMP)mykey $(DIR_TMP)mykey.pub
	$(EXE_MAN) config genkey $(DIR_TMP)mykey
	rm -f $(DIR_TMP)mykey $(DIR_TMP)mykey.pub
	$(EXE_MAN) config genkey $(DIR_TMP)mykey 4096
	$(EXE_BEG_ERR) config genkey $(DIR_TMP)mykey not_int$(EXE_END_ERR)
	@$(STOP_TEST) $@
$(T)conf_smtp: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config email_test --notif-to=@preset:misc.email_external
	@$(STOP_TEST) $@
$(T)conf_pac: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config proxy_check --fpac=@file:$(DIR_TOP)examples/proxy.pac https://eudemo.asperademo.com --proxy-credentials=@list:,user,pass
	@$(STOP_TEST) $@
$(T)conf_check_gem: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config check_update
	rm -f $(CLI_HOME)persist_store/version_last_check.txt
	$(EXE_MAN) config check_update
	@$(STOP_TEST) $@
$(T)conf_doc: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config doc
	$(EXE_MAN) config doc transfer-parameters
	@$(STOP_TEST) $@
$(T)conf_echo: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config echo hello
	$(EXE_MAN) config echo @uri:/etc/hosts
	$(EXE_MAN) config echo @uri:file:/etc/hosts
	$(EXE_MAN) config echo @uri:http://ifconfig.me
	$(EXE_MAN) config echo @uri:https://ifconfig.me
	$(EXE_MAN) config echo @base64:SGVsbG8gV29ybGQK
	$(EXE_MAN) config echo @list:,1,2,3
	$(EXE_MAN) config echo @env:USER
	$(EXE_BEG_ERR) config echo @val:@file:no_such_file$(EXE_END_ERR)
	echo $$'1\n2\n3'|$(EXE_MAN) config echo @lines:@stdin:
	echo $$'t1,t2,t3\na,b,d\nd,e,f'|$(EXE_MAN) config echo @csvt:@stdin:
	ruby -rzlib -e'puts Zlib::Deflate.deflate("Hello World")'|$(EXE_MAN) config echo @zlib:@stdin:
	set -xe&&\
	for f in text ruby json jsonpp yaml table csv;do \
	  $(EXE_NOMAN) config echo @json:'{"user1":"yes","user2":"no"}' --format=$$f;\
	done
	@$(STOP_TEST) $@
$(T)conf_interactive: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config echo @secret:
	@$(STOP_TEST) $@
$(T)conf_hint: $(T).exists
	@$(START_TEST) $@
	$(EXE_BEG_ERR) config throw Aspera::Fasp::Error     'Remote host is not who we expected'$(EXE_SHW_ERR)
	$(EXE_BEG_ERR) config throw OpenSSL::SSL::SSLError  'does not match the server certificate'$(EXE_SHW_ERR)
	$(EXE_BEG_ERR) config throw OpenSSL::SSL::SSLError  'certificate verify failed'$(EXE_SHW_ERR)
	$(EXE_BEG_ERR) config throw Aspera::RestCallError   'Signature has expired'$(EXE_SHW_ERR)
	$(EXE_BEG_ERR) config throw OpenSSL::PKey::RSAError 'Neither PUB key nor PRIV key'$(EXE_SHW_ERR)
	@$(STOP_TEST) $@
tconfig: $(T)conf_ascp_1 $(T)conf_ascp_2 $(T)conf_ascp_3 $(T)conf_ascp_4 $(T)conf_ascp_5 $(T)conf_ascp_6 $(T)conf_ascp_7 $(T)conf_ascp_8 $(T)conf_pset_1 $(T)conf_pset_2 $(T)conf_pset_3 $(T)conf_pset_4 $(T)conf_pset_5 $(T)conf_pset_6 $(T)conf_open $(T)conf_list $(T)conf_over $(T)conf_gem $(T)conf_vault $(T)conf_help $(T)conf_plugins $(T)conf_wizard_org $(T)conf_wizard_gen $(T)conf_detect $(T)conf_genkey $(T)conf_smtp $(T)conf_pac $(T)conf_check_gem $(T)conf_doc $(T)conf_echo $(T)conf_hint

$(T)prev_check: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview check --skip-types=office
	@$(STOP_TEST) $@
$(T)prev_dcm: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview test --base=$(DIR_TMP)$$(basename $@) @preset:file.dcm
	@$(STOP_TEST) $@
$(T)prev_pdf: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.pdf
	@$(STOP_TEST) $@
$(T)prev_docx: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.docx
	@$(STOP_TEST) $@
$(T)prev_mxf_blend: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview test --base=$(DIR_TMP)$$(basename $@) @preset:file.mxf mp4 --video-conversion=blend --query=@json:'{"text":true,"double":true}'
	@$(STOP_TEST) $@
$(T)prev_mpg_png_fix: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg --video-png-conv=fixed
	@$(STOP_TEST) $@
$(T)prev_mpg_png_ani: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg --video-png-conv=animated
	@$(STOP_TEST) $@
$(T)prev_mpg_reencode: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg mp4 --video-conversion=reencode
	@$(STOP_TEST) $@
$(T)prev_mpg_clips: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg mp4 --video-conversion=clips
	@$(STOP_TEST) $@
$(T)prev_events: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) --preset=preview_ak node upload @preset:file.mxf @preset:file.docx --ts=@json:'{"target_rate_kbps":1000000}'
	sleep 4
	$(EXE_MAN) preview trevents --once-only=yes --skip-types=office --log-level=info
	@$(STOP_TEST) $@
$(T)prev_scan: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview scan --skip-types=office --log-level=info
	@$(STOP_TEST) $@
$(T)prev_folder: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) preview scan --scan-id=1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
	@$(STOP_TEST) $@
tprev: $(T)prev_check $(T)prev_dcm $(T)prev_pdf $(T)prev_docx $(T)prev_mpg_png_fix $(T)prev_mpg_png_ani $(T)prev_mxf_blend $(T)prev_mpg_reencode $(T)prev_mpg_clips $(T)prev_events $(T)prev_scan $(T)prev_folder

# TODO : finalize
thot:
	rm -fr source_hot
	mkdir source_hot
	$(EXE_BEG_IGN) server delete @extend:@preset:server.upload_folder@/target_hot$(EXE_END_IGN)
	$(EXE_MAN) server mkdir @extend:@preset:server.upload_folder@/target_hot
	echo hello > source_hot/newfile
	$(EXE_MAN) server upload --to-folder=@extend:@preset:server.upload_folder@/target_hot --lock-port=12345 --transfer-info=@json:'{"ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse @extend:@preset:server.upload_folder@/target_hot
	ls -al source_hot
	sleep 10
	$(EXE_MAN) server upload --to-folder=@extend:@preset:server.upload_folder@/target_hot --lock-port=12345 --transfer-info=@json:'{"ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse @extend:@preset:server.upload_folder@/target_hot
	ls -al source_hot
	rm -fr source_hot
	@$(STOP_TEST) $@

$(T)tcos_info1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) cos -N --bucket=@preset:icos.bucket_name --region=@preset:icos.bucket_region --service-credentials=@json:@file:$(DIR_PRIV)service_creds.json node info
	@$(STOP_TEST) $@
$(T)tcos_info2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) cos -N --bucket=@preset:icos.bucket_name --endpoint=@preset:icos.bucket_endpoint --apikey=@preset:icos.bucket_apikey --crn=@preset:icos.resource_instance_id node info
	@$(STOP_TEST) $@
$(T)tcos_info3: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) cos node info
	@$(STOP_TEST) $@
$(T)tcos_show: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) cos node access_key show self
	@$(STOP_TEST) $@
$(T)tcos_upload: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) cos node upload $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(T)tcos_download: $(T)tcos_upload
	@$(START_TEST) $@
	$(EXE_MAN) cos node download $(TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
tcos: $(T)tcos_info1 $(T)tcos_info2 $(T)tcos_info3 $(T)tcos_show $(T)tcos_upload $(T)tcos_download

$(T)f5_nagios: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 health
	$(EXE_BEG_ERR) faspex5 health --url=https://wrong.example --format=nagios$(EXE_END_ERR)
	@$(STOP_TEST) $@
$(T)f5_p1: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 packages receive INIT --once-only=yes
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":[{"name":"@preset:faspex5_user.username@"}]@preset:faspex5.meta@}' $(TST_ASC_LCL_PATH) --ts=@json:'{"content_protection_password":"my_passphrase_here"}'
	@$(STOP_TEST) $@
$(T)f5_p2: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 packages list --query=@json:'{"mailbox":"inbox","state":["released"]}'
	@$(STOP_TEST) $@
$(T)f5_sh_folder_list: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 shared_folders list
	@$(STOP_TEST) $@
$(T)f5_sh_folder_br: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 shared_folders browse @extend:%name:@preset:faspex5.shfolder_name@
	@$(STOP_TEST) $@
$(T)f5_sh_folder_send: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 packages send --shared-folder=@extend:%name:@preset:faspex5.shfolder_name@ @json:@extend:'{"title":"test title","recipients":["@preset:misc.email_internal@"]}' @preset:faspex5.shfolder_file
	@$(STOP_TEST) $@
$(T)f5_p3: $(T).exists
	@$(START_TEST) $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --query=@json:'{"mailbox":"inbox","state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages status "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive "$${package_id}" --to-folder=$(DIR_TMP).  --ts=@json:'{"content_protection_password":"abc123_yo"}'
	$(EXE_MAN) faspex5 packages receive ALL --once-only=yes --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(T)f5_pack_shbox: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:faspex5.shinbox@"],"metadata":{"Options":"Opt1","TextInput":"example text"}}' $(TST_ASC_LCL_PATH)
	$(EXE_MAN) faspex5 packages list --box=@preset:faspex5.shinbox
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --box=@preset:faspex5.shinbox --query=@json:'{"state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show --box=@preset:faspex5.shinbox "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive --box=@preset:faspex5.shinbox "$${package_id}" --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(T)f5_pack_wrkgrp: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:faspex5.workgroup@"]}' $(TST_ASC_LCL_PATH)
	$(EXE_MAN) faspex5 packages list --box=@preset:faspex5.workgroup --group-type=workgroups
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --box=@preset:faspex5.workgroup --group-type=workgroups --query=@json:'{"state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show --box=@preset:faspex5.workgroup --group-type=workgroups "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive --box=@preset:faspex5.workgroup --group-type=workgroups "$${package_id}" --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(T)f5_sh_fold: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 shared list
	$(EXE_MAN) faspex5 shared browse %name:@preset:faspex4.src
	@$(STOP_TEST) $@
$(T)f5_user_res: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 bearer_token
	$(EXE_MAN) faspex5 admin res contacts list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res shared_inboxes list
	$(EXE_MAN) faspex5 admin res shared_inboxes members %name:'ascli shinbox' list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res saml_configs list
	$(EXE_MAN) faspex5 admin res metadata_profiles list
	@$(STOP_TEST) $@
$(T)f5_adm: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) --preset=f5_admin faspex5 admin res accounts list
	$(EXE_MAN) --preset=f5_admin faspex5 admin res jobs list
	$(EXE_MAN) --preset=f5_admin faspex5 admin res node list 
	$(EXE_MAN) --preset=f5_admin faspex5 admin res oauth_clients list
	$(EXE_MAN) --preset=f5_admin faspex5 admin res registrations list
	$(EXE_MAN) --preset=f5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' create %name:john@example.com
	$(EXE_MAN) --preset=f5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' delete %name:john@example.com
	$(EXE_MAN) --preset=f5_admin faspex5 admin res shared_inboxes invite %name:'ascli shinbox' johnny@example.com
	$(EXE_MAN) --preset=f5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' delete %name:johnny@example.com
	$(EXE_MAN) --preset=f5_admin faspex5 admin smtp show
	$(EXE_MAN) --preset=f5_admin faspex5 admin smtp test @preset:misc.email_external
	@$(STOP_TEST) $@
$(T)f5_user: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 user profile show
	$(EXE_MAN) faspex5 user profile modify @json:'{"preference":{"connect_disabled":false}}'
	@$(STOP_TEST) $@
$(T)f5_error: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) faspex5 health --url=wrong
	@$(STOP_TEST) $@
$(T)f5_webauth: $(T).exists
	@$(START_TEST) $@
	$(EXE_NOMAN) --preset=f5_web faspex5 version
	@$(STOP_TEST) $@
$(T)f5_wizard: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:faspex5_user.url faspex5 --pkeypath=@preset:file.private_key --preset=faspex5_user
	$(EXE_BEG_ERR) config detect https://eudemo.asperademo.com:22 faspex5$(EXE_END_ERR)
	$(EXE_MAN) -N config detect @preset:faspex5_user.url
	$(EXE_NOMAN) config detect @preset:faspex5_user.url
	@$(STOP_TEST) $@
$(T)f5_fxgw: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 gateway --pid-file=$(DIR_TMP)server_pid https://localhost:12345/aspera/faspex & sleep 4
	$(EXE_NOMAN) -N faspex --url=https://localhost:12345/aspera/faspex --username=_unused_ --password=_unused_ --insecure=yes package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway faspex 5"}' 'faux:///test1?1m'
	sleep 3
	kill -USR1 $$(cat $(DIR_TMP)server_pid)
	@$(STOP_TEST) $@
$(T)f5_postproc: $(T).exists
	@$(START_TEST) $@
	$(EXE_MAN) faspex5 postprocessing --pid-file=$(DIR_TMP)server_pid @json:'{"url":"https://localhost:8443/domain","processing":{"script_folder":"tests"}}' & sleep 10
	kill -INT $$(cat $(DIR_TMP)server_pid)
	@$(STOP_TEST) $@

tf5: $(T)f5_nagios $(T)f5_p1 $(T)f5_p2 $(T)f5_p3 $(T)f5_sh_folder_list $(T)f5_sh_folder_br $(T)f5_sh_folder_send $(T)f5_pack_shbox $(T)f5_pack_wrkgrp $(T)f5_user_res $(T)f5_adm $(T)f5_user $(T)f5_error $(T)f5_wizard $(T)f5_fxgw $(T)f5_sh_fold $(T)f5_postproc
