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

# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
DIR_CONNECT_DOWNLOAD=$(HOME)/Downloads
TIMESTAMP=$(shell LANG=C date)

# temp conf file that is modified, to avoid the test configuration file
TEST_CONFIG=$(DIR_TMP)sample.conf
TMP_CONF=--config-file=$(TEST_CONFIG)
WIZ_TEST=--test-mode=yes
# tests use config file in test folder
EXE_COMMON=$(EXETESTB) --config-file=$(TEST_CONF_FILE_PATH)
# "EXE_MAN" and "EXE_NOMAN" are used to call the tool in the testing environment
# "EXE_MAN" is used to generate sample commands in documentation (see in docs/Makefile)
EXE_MAN=$(EXE_COMMON) --warnings
# "EXE_NOMAN" when the command is not needed in documentation
EXE_NOMAN=$(EXE_COMMON)
# enclose tests that shall result in error
EXE_BEG_ERR=if $(EXE_COMMON)
EXE_END_ERR=>/dev/null 2>&1;then echo "No error: problem";exit 1;else echo "Test ok";fi
# enclose tests that fail, but should not
EXE_BEG_FAI=if $(EXE_COMMON)
EXE_END_FAI=>/dev/null 2>&1;then echo "TODO: test worked, restore test?";else echo "Test known to fail";fi
# enclose tests whose status is ignored, mainly optional cleanups, for restarts
EXE_BEG_IGN=$(EXE_COMMON)
EXE_END_IGN=>/dev/null 2>&1 || true
# testing file generated locally (special shell characters must be escaped for shell, special makefile characters escaped)
LCL_TST_ASC_FILENAME=datafile.bin
LCL_TST_ASC_FILEPATH=$(DIR_TMP)$(LCL_TST_ASC_FILENAME)
LCL_TST_UTF_FILENAME='spécial{\#😀"'
LCL_TST_UTF_FILEPATH=$(DIR_TMP)$(LCL_TST_UTF_FILENAME)
# sync dir must be an absolute path
LCL_SYNC_DIR=$(shell realpath "$(DIR_TMP)")/testsync123

ifeq ($(LCL_SYNC_DIR),)
$(error "LCL_SYNC_DIR is empty, see error above")
endif

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
	echo 'This is a small test file' > $(LCL_TST_ASC_FILEPATH)
	echo 'This is a small test file' > $(LCL_TST_UTF_FILEPATH)
	@touch $@
clean::
	rm -f $(LCL_TST_ASC_FILEPATH) $(LCL_TST_UTF_FILEPATH)
	rm -fr $(T)
	rm -f $(DIR_TOP).rspec_status
$(T)unit: $(T).exists
	@echo $@
	set -x&&\
	CF_HSTS_SSH_URL=$$($(EXE_NOMAN) config preset get tst_server url) \
	CF_HSTS_SSH_USER=$$($(EXE_NOMAN) config preset get tst_server username) \
	CF_HSTS_SSH_PASS=$$($(EXE_NOMAN) config preset get tst_server password) \
	bundle exec rake spec
	@touch $@
tunit: $(T)unit
$(T)shares_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) shares health
	$(EXE_NOMAN) shares health --url=https://wrong.example.com
	@touch $@
$(T)shares_wizard: $(T).exists
	@echo $@
	$(EXE_MAN) config detect @preset:tst_shares.url shares
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_shares.url shares --username=test --password=test
	@touch $@
$(T)shadm: $(T).exists
	@echo $@
	$(EXE_MAN) shares admin node list
	$(EXE_MAN) shares admin group list
	$(EXE_MAN) shares admin user list
	$(EXE_MAN) shares admin user list --type=local
	$(EXE_MAN) shares admin user app_authorizations 1 show
	$(EXE_MAN) shares admin user app_authorizations 1 modify @json:'{"app_login":true}'
	$(EXE_MAN) shares admin user share_permissions 1 list
	$(EXE_MAN) shares admin user share_permissions 1 show 1
	$(EXE_MAN) shares admin user import --type=saml @json:'{"id":"the_id","name_id":"the_name"}'
	$(EXE_BEG_FAI) shares admin user add --type=ldap the_name $(EXE_END_FAI)
	$(EXE_MAN) shares admin share list --fields=DEF,-status,status_message
	$(EXE_MAN) shares admin share user_permissions 1 list
	@touch $@
$(T)sh1: $(T).exists
	@echo $@
	$(EXE_MAN) shares files browse /
	@touch $@
$(T)sh2: $(T).exists
	@echo $@
	$(EXE_MAN) shares files upload --to-folder=@preset:misc.shares_upload $(LCL_TST_ASC_FILEPATH)
	$(EXE_MAN) shares files download --to-folder=$(DIR_TMP). @extend:@preset:misc.shares_upload@/$(LCL_TST_ASC_FILENAME)
	$(EXE_MAN) shares files delete @extend:@preset:misc.shares_upload@/$(LCL_TST_ASC_FILENAME)
	@touch $@
$(T)sh3: $(T).exists
	@echo $@
	$(EXE_MAN) shares files upload --to-folder=@preset:misc.shares_upload $(LCL_TST_ASC_FILEPATH) --transfer=httpgw -Pnowss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy"}'
	$(EXE_MAN) shares files upload --to-folder=@preset:misc.shares_upload 'faux:///testfile?1m' --transfer=httpgw -Pnowss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy","synchronous":true,"api_version":"v1","upload_chunk_size":100000}'
	$(EXE_MAN) shares files download --to-folder=$(DIR_TMP). @extend:@preset:misc.shares_upload@/$(LCL_TST_ASC_FILENAME) --transfer=httpgw -Pnowss --transfer-info=@json:@extend:'{"url":"https://@preset:misc.http_gw_fqdn_port@/aspera/http-gwy"}'
	$(EXE_MAN) shares files delete @extend:@preset:misc.shares_upload@/$(LCL_TST_ASC_FILENAME)
	@touch $@
tshares: $(T)shares_nagios $(T)shares_wizard $(T)shadm $(T)sh1 $(T)sh2 $(T)sh3

$(T)serv_browse: $(T).exists
	@echo $@
	$(EXE_MAN) server browse /
	@touch $@
$(T)serv_mkdir: $(T).exists
	@echo $@
	$(EXE_MAN) server mkdir @preset:misc.server_folder --logger=stdout
	@touch $@
$(T)serv_error: $(T).exists
	@echo $@
	$(EXE_BEG_ERR) server --password=wrong upload $(LCL_TST_ASC_FILEPATH) --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server --password=wrong browse / --ssh-options=@json:'{"number_of_password_prompts":0}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=foo:// ls .$(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=@preset:tst_node_simple.url upload wrong --ts=@json:'{"token":"test"}' --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_BEG_ERR) server -N --url=@preset:tst_node_simple.url upload wrong --transfer-info=@json:'{"resume":{"iter_max":0}}' $(EXE_END_ERR)
	$(EXE_NOMAN) server -N --url=local:// ls .
	@touch $@
$(T)serv_upload: $(T)serv_mkdir 
	@echo $@
	$(EXE_MAN) server upload $(LCL_TST_ASC_FILEPATH) --to-folder=@preset:misc.server_folder --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":1500}' --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}' --progress=multi
	$(EXE_MAN) server browse @extend:@preset:misc.server_folder@/$(LCL_TST_ASC_FILENAME)
	$(EXE_MAN) server upload --src-type=pair $(LCL_TST_ASC_FILEPATH) @extend:@preset:misc.server_folder@/othername --notif-to=@preset:misc.email_external --transfer-info=@json:'{"ascp_args":["-l","10m"]}'
	$(EXE_MAN) server upload --src-type=pair --sources=@json:@extend:'["$(LCL_TST_ASC_FILEPATH)","@preset:misc.server_folder@/othername"]'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:@extend:'{"paths":[{"source":"$(LCL_TST_ASC_FILEPATH)","destination":"@preset:misc.server_folder@/othername"}]}'
	$(EXE_MAN) server upload --src-type=pair $(LCL_TST_ASC_FILEPATH) @extend:@preset:misc.upload_folder@/with_options --ts=@json:'{"cipher":"aes-192-gcm","content_protection":"encrypt","content_protection_password":"my_secret_here","cookie":"biscuit","create_dir":true,"delete_before_transfer":false,"delete_source":false,"exclude_newer_than":1,"exclude_older_than":10000,"fasp_port":33001,"http_fallback":false,"multi_session":0,"overwrite":"diff+older","precalculate_job_size":true,"preserve_access_time":true,"preserve_creation_time":true,"rate_policy":"fair","resume_policy":"sparse_csum","symlink_policy":"follow"}'
	@touch $@
$(T)serv_sync: $(T)serv_upload 
	@echo $@
	rm -fr $(LCL_SYNC_DIR)
	mkdir -p $(LCL_SYNC_DIR)
	$(EXE_MAN) server sync start --sync-info=@json:@extend:'{"instance":{"quiet":false},"sessions":[{"name":"mysync","direction":"pull","remote_dir":"@preset:misc.server_folder@","local_dir":"$(LCL_SYNC_DIR)","reset":true}]}'
	$(EXE_MAN) server sync admin status mysync --sync-info=@json:'{"sessions":[{"name":"mysync","local_dir":"$(LCL_SYNC_DIR)"}]}'
	$(EXE_MAN) server sync start --sync-info=@json:@extend:'{"name":"sync2","local":{"path":"$(LCL_SYNC_DIR)"},"remote":{"path":"@preset:misc.server_folder@"},"reset":true,"quiet":false}'
	$(EXE_BEG_FAI) server sync admin status --sync-info=@json:'{"name":"sync2"}' $(EXE_END_FAI)
	$(EXE_MAN) server sync admin status --sync-info=@json:'{"name":"sync2","local":{"path":"$(LCL_SYNC_DIR)"}}'
	@touch $@
$(T)serv_upload_ex: $(T)serv_mkdir
	echo $(LCL_TST_ASC_FILEPATH) > $(DIR_TMP)filelist.txt
	echo $(LCL_TST_ASC_FILEPATH) > $(DIR_TMP)filepairlist.txt
	$(EXE_NOMAN) config echo @extend:@preset:misc.server_folder@/othername --format=text >> $(DIR_TMP)filepairlist.txt
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_file_list":"'"$(DIR_TMP)filelist.txt"'"}' --to-folder=@preset:misc.server_folder
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_file_pair_list":"'"$(DIR_TMP)filepairlist.txt"'"}'
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-list","'"$(DIR_TMP)filelist.txt"'"]}' --to-folder=@preset:misc.server_folder 
	$(EXE_MAN) server upload --sources=@ts --ts=@json:'{"EX_ascp_args":["--file-pair-list","'"$(DIR_TMP)filepairlist.txt"'"]}'
	@touch $@
$(T)serv_md5: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server md5sum @extend:@preset:misc.server_folder@/$(LCL_TST_ASC_FILENAME)
	@touch $@
$(T)serv_down_lcl: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server download @extend:@preset:misc.server_folder@/$(LCL_TST_ASC_FILENAME) --to-folder=$(DIR_TMP). --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
	@touch $@
$(T)serv_down_from_node: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server download @extend:@preset:misc.server_folder@/$(LCL_TST_ASC_FILENAME) --to-folder=@preset:misc.upload_folder --transfer=node
	@touch $@
$(T)serv_cp: $(T)serv_upload
	@echo $@
	$(EXE_MAN) server cp @extend:@preset:misc.server_folder@/$(LCL_TST_ASC_FILENAME) @extend:@preset:misc.upload_folder@/200KB.2
	@touch $@
$(T)serv_mv: $(T)serv_cp
	@echo $@
	$(EXE_MAN) server mv @extend:@preset:misc.upload_folder@/200KB.2 @extend:@preset:misc.upload_folder@/to.delete
	@touch $@
$(T)serv_delete: $(T)serv_mv
	@echo $@
	$(EXE_MAN) server delete @extend:@preset:misc.upload_folder@/to.delete
	@touch $@
$(T)serv_cleanup1: $(T).exists
	@echo $@
	$(EXE_MAN) server delete @preset:misc.server_folder
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
$(T)serv_nagios_transfer: $(T).exists
	@echo $@
	$(EXE_MAN) server health transfer --to-folder=@preset:misc.upload_folder --format=nagios 
	$(EXE_BEG_ERR) server health transfer --to-folder=/wrong --format=nagios$(EXE_END_ERR)
	@touch $@
$(T)serv_key: $(T).exists
	@echo $@
	$(EXE_MAN) server -N -Ptst_server_bykey browse /
	@touch $@
$(T)asession: $(T).exists
	@echo $@
	set -x&&\
	remote_host=$$($(EXE_NOMAN) config preset get tst_server url)&&\
	remote_host=$${remote_host##*/}&&remote_port="$remote_host"&&\
	remote_port=$${remote_host#*:}&&remote_host=$${remote_host%:*}&&\
	$(DIR_BIN)asession @json:@extend:'{"remote_host":"'"$${remote_host}"'","remote_user":"@preset:tst_server.username@","ssh_port":'$${remote_port}',"remote_password":"@preset:tst_server.password@","direction":"receive","destination_root":"$(DIR_TMP).","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}]}'
	@touch $@
tserver: $(T)serv_error $(T)serv_browse $(T)serv_mkdir $(T)serv_upload $(T)serv_sync $(T)serv_upload_ex $(T)serv_md5 $(T)serv_down_lcl $(T)serv_down_from_node $(T)serv_cp $(T)serv_mv $(T)serv_delete $(T)serv_cleanup1 $(T)serv_info $(T)serv_du $(T)serv_df $(T)asession $(T)serv_nagios_transfer $(T)serv_key

$(T)f4_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) faspex health
	$(EXE_NOMAN) faspex health --url=https://wrong.example.com
	@touch $@
$(T)f4_wizard: $(T).exists
	@echo $@
	$(EXE_NOMAN) config detect @preset:tst_faspex4.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_faspex4.url faspex --username=test --password=test
	@touch $@
$(T)f4_plst: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package list --query=@json:'{"max":5}'
	@touch $@
$(T)f4_psnd: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_internal@","@preset:tst_faspex4.username@"]}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
	@sleep 8
$(T)f4_prs: $(T)f4_psnd
	@echo $@
	set -x&&\
	package_id=$$($(EXE_MAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	set -x&&\
	package_id=$$($(EXE_MAN) faspex package list --box=sent --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP). --box=sent
	@touch $@
$(T)f4_pri: $(T).exists
	@echo $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex package list --fields=package_id --format=csv --display=data --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv "$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@
$(T)f4_prl: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package recv --to-folder=$(DIR_TMP). --link=@preset:faspex4_publink.link_recv_from_user
	@touch $@
$(T)f4_prall: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package recv ALL --to-folder=$(DIR_TMP). --once-only=yes --query=@json:'{"max":10}'
	@touch $@
$(T)f4_pslu: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package send --link=@preset:faspex4_publink.link_send_to_user --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)f4_psld: $(T).exists
	@echo $@
	$(EXE_MAN) faspex package send --link=@preset:faspex4_publink.link_send_to_dropbox --delivery-info=@json:'{"title":"Test Package $(TIMESTAMP)"}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)f4_remote_src: $(T).exists
	@echo $@
	$(EXE_MAN) faspex source list
	$(EXE_MAN) faspex source info %name:@preset:misc.faspex_src --storage=@preset:faspex4_storage
	$(EXE_MAN) faspex source node %name:@preset:misc.faspex_src br / --storage=@preset:faspex4_storage
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"$(TIMESTAMP) package remote","recipients":["@preset:misc.email_internal@"]}' --remote_source=@extend:%name:@preset:misc.faspex_src sample_source.txt
	@touch $@
$(T)f4_misc: $(T).exists
	@echo $@
	$(EXE_MAN) faspex me
	$(EXE_MAN) faspex address_book
	$(EXE_MAN) faspex login_methods
	@touch $@
$(T)f4_v4: $(T).exists
	@echo $@
	$(EXE_MAN) -Ptst_faspex4_admin faspex v4 dropbox list
	$(EXE_MAN) -Ptst_faspex4_admin faspex v4 dmembership list
	$(EXE_MAN) faspex v4 workgroup list
	$(EXE_MAN) faspex v4 wmembership list
	$(EXE_MAN) faspex v4 user list
	$(EXE_MAN) faspex v4 metadata_profile list
	@touch $@
$(T)f4_db1: $(T).exists
	@echo $@
	$(EXE_MAN) faspex dropbox list --recipient=@extend:"*@preset:misc.faspex_dbx@"
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["*@preset:misc.faspex_dbx@"]}' $(LCL_TST_ASC_FILEPATH)
	set -x&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient=@extend:"*@preset:misc.faspex_dbx@" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient=@extend:"*@preset:misc.faspex_dbx@" --to-folder=$(DIR_TMP).
	$(EXE_MAN) faspex dropbox list --recipient=@extend:"*@preset:misc.faspex_dbx@"
	$(EXE_MAN) faspex package send --delivery-info=@json:@extend:'{"title":"Test Package $(TIMESTAMP)","recipients":["*@preset:misc.faspex_wkg@"]}' $(LCL_TST_ASC_FILEPATH)
	set -x&&\
	pkgid=$$($(EXE_MAN) faspex package list --recipient=@extend:"*@preset:misc.faspex_wkg@" --format=csv --fields=package_id --query=@json:'{"max":1}')&&\
	$(EXE_MAN) faspex package recv $${pkgid} --recipient=@extend:"*@preset:misc.faspex_wkg@" --to-folder=$(DIR_TMP).
	@touch $@
tfaspex: $(T)f4_nagios $(T)f4_wizard $(T)f4_plst $(T)f4_psnd $(T)f4_prs $(T)f4_pri $(T)f4_pslu $(T)f4_psld $(T)f4_remote_src $(T)f4_prall $(T)f4_misc $(T)f4_v4 $(T)f4_db1
#  $(T)f4_prl
$(T)cons_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) console health
	$(EXE_NOMAN) console health --url=https://wrong.example.com
	@touch $@
$(T)cons_wizard: $(T).exists
	@echo $@
	$(EXE_NOMAN) config detect @preset:tst_console.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_console.url console -Ptst_console
	@touch $@
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
	$(EXE_MAN) console transfer smart sub @preset:misc.console_smart_id @json:@extend:'{"source":{"paths":["@preset:misc.console_smart_file@"]},"source_type":"user_selected"}'
	@touch $@
tconsole: $(T)cons_nagios $(T)cons_wizard $(T)cons1 $(T)cons2
#  $(T)cons3
$(T)nd_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) node health
	$(EXE_NOMAN) node health --url=https://wrong.example.com
	@touch $@
$(T)nd_wizard: $(T).exists
	@echo $@
	$(EXE_MAN) config detect @preset:tst_node_simple.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_node_simple.url node --username=test --password=test
	@touch $@
$(T)nd1: $(T).exists
	@echo $@
	$(EXE_MAN) node info --fpac='function FindProxyForURL(url,host){return "DIRECT"}'
	$(EXE_MAN) node license
	$(EXE_MAN) node api_details
	$(EXE_MAN) node browse / -r
	$(EXE_MAN) node search / --query=@json:'{"sort":"mtime"}'
	$(EXE_MAN) node space /
	$(EXE_BEG_IGN) node delete /todelete $(EXE_END_IGN)
	$(EXE_MAN) node mkdir @extend:@preset:misc.upload_folder@/todelete
	$(EXE_MAN) node mklink @extend:@preset:misc.upload_folder@/todelete @extend:@preset:misc.upload_folder@/tdlink
	$(EXE_MAN) node mkfile @extend:@preset:misc.upload_folder@/delfile1 "hello world"
	$(EXE_MAN) node rename @preset:misc.upload_folder delfile1 delfile
	$(EXE_MAN) node delete @list:@extend:,@preset:misc.upload_folder@/todelete,@preset:misc.upload_folder@/tdlink,@preset:misc.upload_folder@/delfile
	@touch $@
$(T)nd2: $(T).exists
	@echo $@
	$(EXE_MAN) node upload $(LCL_TST_ASC_FILEPATH) --to-folder=@preset:misc.upload_folder --ts=@json:'{"target_rate_cap_kbps":10000}'
	$(EXE_MAN) node download @extend:@preset:misc.upload_folder@/$(LCL_TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	$(EXE_MAN) node delete @extend:@preset:misc.upload_folder@/$(LCL_TST_ASC_FILENAME)
	@touch $@
$(T)nd_2_nd_xfer: $(T).exists
	@echo $@
	$(EXE_MAN) node upload --to-folder=@preset:misc.upload_folder --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.2"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:@extend:'{"url":"@preset:tst_node_simple.url@","username":"@preset:tst_node_simple.username@","password":"@preset:tst_node_simple.password@"}'
	$(EXE_BEG_IGN) node delete @extend:@preset:misc.upload_folder@/10MB.2$(EXE_END_IGN)
	@touch $@
$(T)nd4: $(T).exists
	@echo $@
	$(EXE_BEG_IGN) node -Ptst_node_admak service delete service1$(EXE_END_IGN)
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node -Ptst_node_admak service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(EXE_MAN) node -Ptst_node_admak service list
	@echo "waiting a little...";sleep 2
	$(EXE_MAN) node -Ptst_node_admak service delete service1
	$(EXE_MAN) node -Ptst_node_admak service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node -Ptst_node_admak service list
	@echo "waiting a little...";sleep 5
	$(EXE_MAN) node -Ptst_node_admak service list
	@touch $@
# test creation of access key
$(T)nd5: $(T).exists
	@echo $@
	$(EXE_MAN) node -N -Ptst_node_preview access_key create @json:'{"id":"testingAK1","storage":{"type":"local","path":"/"}}'
	sleep 2
	$(EXE_MAN) node -N -Ptst_node_preview access_key delete testingAK1
	@touch $@
$(T)nd6: $(T).exists
	@echo $@
	$(EXE_MAN) node transfer list --query=@json:'{"active_only":true}'
	$(EXE_MAN) node transfer sessions
	@touch $@
$(T)nd7: $(T).exists
	@echo $@
	$(EXE_MAN) node basic_token
	@touch $@
$(T)nd8: $(T).exists
	@echo $@
	$(EXE_MAN) node upload --username=@preset:misc.aoc_ak_name --password=@preset:misc.aoc_ak_secret $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)nd_ak: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak access_key list
	@touch $@
$(T)nd_ak1: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name node_info /
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name browse /
	$(EXE_BEG_ERR)node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name find @json:'{}'$(EXE_END_ERR)
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name find @preset:misc.aoc_folder exec:'f["name"].end_with?(".jpg")'
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name find @preset:misc.aoc_folder @ruby:'->(f){f["name"].end_with?(".jpg")}'
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name find @preset:misc.aoc_folder
	@touch $@
$(T)nd_ak2: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name mkdir /folder1
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name rename /folder1 folder2
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name delete /folder2
	@touch $@
$(T)nd_ak3: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name upload 'faux:///testfile1?1k' --default_ports=no
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name download testfile1 --to-folder=$(DIR_TMP).
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name show /testfile1
	$(EXE_BEG_ERR) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name thumbnail /testfile1$(EXE_END_ERR)
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name delete testfile1
	@touch $@
$(T)nd_ak4: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak access_key do @preset:misc.aoc_ak_name show %id:1
	@touch $@
$(T)nd_ak5: $(T).exists
	@echo $@
	$(EXE_MAN) node -Ptst_node_admak bearer --bearer-key=@preset:tst_aoc_jwt.private_key --token-info=@json:'{"user_id":"1"}'
	@touch $@
tndak: $(T)nd_ak $(T)nd_ak1 $(T)nd_ak2 $(T)nd_ak3 $(T)nd_ak4
tnode: $(T)nd_wizard $(T)nd_nagios $(T)nd1 $(T)nd2 $(T)nd_2_nd_xfer $(T)nd4 $(T)nd5 $(T)nd6 $(T)nd7 $(T)nd8 tndak

$(T)aocfxgw: $(T).exists
	@echo $@
	$(EXE_MAN) aoc gateway https://localhost:12345/aspera/faspex &\
		jobs -p > $(T)server_pid
	sleep 2
	$(EXE_NOMAN) -N faspex --url=https://localhost:12345/aspera/faspex --username=_unused_ --password=_unused_ --insecure=yes package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway aoc"}' 'faux:///test1?1m'
	kill -INT $$(cat $(T)server_pid)
	@touch $@
$(T)aocg1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc -N servers
	$(EXE_MAN) aoc -N remind --username=@preset:misc.aoc_user_email
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
$(T)aoc_webauth: $(T).exists
	@echo $@
	$(EXE_NOMAN) aoc -Ptst_aoc_web user profile show
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
	$(EXE_MAN) aoc files find / '\.partial$$'
	@touch $@
$(T)aocfmkd: $(T).exists
	@echo $@
	$(EXE_BEG_IGN) aoc files delete /testsrc$(EXE_END_IGN)
	$(EXE_MAN) aoc files mkdir /testsrc
	@touch $@
$(T)aocfren: $(T).exists
	@echo $@
	$(EXE_BEG_IGN) aoc files delete /testdst$(EXE_END_IGN)
	$(EXE_NOMAN) aoc files mkdir /somefolder
	$(EXE_MAN) aoc files rename /somefolder testdst
	@touch $@
$(T)aocfupl: $(T)aocfmkd
	@echo $@
	$(EXE_MAN) aoc files upload --to-folder=/testsrc $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)aocftr: $(T)aocfupl $(T)aocfren
	@echo $@
	$(EXE_MAN) aoc files transfer --from-folder=/testsrc --to-folder=/testdst $(LCL_TST_ASC_FILENAME)
	@touch $@
$(T)aocndinf: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files node_info --workspace=@preset:misc.aoc_workspace2 /myfolder --format=json --display=data | $(EXE_MAN) aoc files upload Test.pdf --transfer=node --transfer-info=@json:@stdin:
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
	@-killall asperaconnect
	@sleep 1
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
$(T)aocfsync1: $(T).exists
	@echo $@
	rm -fr $(LCL_SYNC_DIR)
	mkdir -p $(LCL_SYNC_DIR)
	$(EXE_MAN) aoc files sync start --sync-info=@json:'{"sessions":[{"name":"my_aoc_sync1","direction":"pull","local_dir":"$(LCL_SYNC_DIR)","remote_dir":"/testdst","reset":true}]}'
	$(EXE_MAN) aoc files sync admin status --sync-info=@json:'{"sessions":[{"name":"my_aoc_sync1","direction":"pull","local_dir":"$(LCL_SYNC_DIR)","remote_dir":"/testdst","reset":true}]}'
	@touch $@
$(T)aocfsync2: $(T).exists
	@echo $@
	rm -fr $(LCL_SYNC_DIR)
	mkdir -p $(LCL_SYNC_DIR)
	$(EXE_BEG_FAI) aoc files sync start --sync-info=@json:'{"name":"my_aoc_sync2","reset":true,"direction":"pull","local":{"path":"$(LCL_SYNC_DIR)"},"remote":{"path":"/testdst"}}'$(EXE_END_FAI)
	$(EXE_BEG_FAI) aoc files sync admin status --sync-info=@json:'{"name":"my_aoc_sync2","reset":true,"direction":"pull","local":{"path":"$(LCL_SYNC_DIR)"},"remote":{"path":"/testdst"}}'$(EXE_END_FAI)
	@touch $@
$(T)aocffid: $(T).exists
	@echo $@
	set -x&&\
	file_id=$$($(EXE_NOMAN) aoc files br /200KB.1 --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) aoc files show %id:$${file_id}
	$(EXE_MAN) aoc files show /200KB.1
	$(EXE_MAN) aoc files permission @preset:misc.aoc_test_folder list
	$(EXE_MAN) aoc files thumbnail @preset:misc.aoc_media_file
	$(EXE_MAN) aoc files thumbnail @preset:misc.aoc_media_file --query=@json:'{"text":true,"double":true}'
	$(EXE_NOMAN) aoc files thumbnail @preset:misc.aoc_media_file --query=@json:'{"text":true,"double":false}'
	env -u TERM_PROGRAM -u LC_TERMINAL $(EXE_NOMAN) aoc files thumbnail @preset:misc.aoc_media_file
	@touch $@
#	$(EXE_MAN) aoc files modify @preset:misc.aoc_test_folder
$(T)aocfpub: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files browse / -N --link=@preset:misc.aoc_publink_folder_nopass
	$(EXE_MAN) aoc files browse / -N --link=@preset:misc.aoc_publink_folder_pass --password=@preset:misc.aoc_publink_password
	$(EXE_MAN) aoc files upload -N --to-folder=/ $(LCL_TST_ASC_FILEPATH) --link=@preset:misc.aoc_publink_folder_nopass
	@touch $@
$(T)aocshlk1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link list /testdst private
	@touch $@
$(T)aocshlk2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link create /testdst private
	@touch $@
$(T)aocshlk3: $(T).exists
	@echo $@
	$(EXE_MAN) aoc files short_link create testdst public
	@touch $@
taocf: $(T)aocfbr $(T)aocfbt $(T)aocffin $(T)aocfmkd $(T)aocfren $(T)aocfupl $(T)aocftr $(T)aocndinf $(T)aocfdel $(T)aocfbearnode $(T)aocfdown $(T)aocfhttpd $(T)aocfv3inf $(T)aocfsync1 $(T)aocfsync2 $(T)aocffid $(T)aocfpub $(T)aocshlk1 $(T)aocshlk2 $(T)aocshlk3 $(T)aocfxgw
$(T)aocp1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_internal@"],"note":"my note"}' $(LCL_TST_ASC_FILEPATH)
	$(EXE_MAN) aoc packages send @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.email_external@"]}' --new-user-option=@json:'{"package_contact":true}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)aocp2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages list
	@touch $@
$(T)aocp3: $(T).exists
	@echo $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) aoc packages list --format=csv --fields=id --display=data|head -n 1)&&\
	$(EXE_MAN) aoc packages recv "$${package_id}" --to-folder=$(DIR_TMP).&&\
	$(EXE_MAN) aoc packages browse "$${package_id}" /contents
	@touch $@
$(T)aocp4: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages recv ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345
	@touch $@
$(T)aocp5: $(T).exists
	@echo $@
	$(EXE_MAN) aoc org -N --link=@preset:misc.aoc_publink_recv_from_aocuser
	@touch $@
$(T)aocp_send_pub_sh: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send -N @json:'{"name":"Test Package $(TIMESTAMP)"}' $(LCL_TST_ASC_FILEPATH) --link=@preset:misc.aoc_publink_send_shd_inbox
	@touch $@
$(T)aocp_send_pub_usr: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send -N @json:'{"name":"Test Package $(TIMESTAMP)"}' $(LCL_TST_ASC_FILEPATH) --link=@preset:misc.aoc_publink_send_aoc_user --password=@preset:misc.aoc_publink_send_use_pass
	@touch $@
$(T)aocp_send_shbx: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send --workspace=@preset:misc.aoc_shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.aoc_shbx_name@"]}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)aocp_send_sh_meta_long: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send --workspace=@preset:misc.aoc_shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.aoc_shbx_name@"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)aocp_send_sh_meta_short: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages send --workspace=@preset:misc.aoc_shbx_ws @json:@extend:'{"name":"Test Package $(TIMESTAMP)","recipients":["@preset:misc.aoc_shbx_name@"],"metadata":{"Project Id":"456","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' $(LCL_TST_ASC_FILEPATH)
	@touch $@
$(T)aocp_recv_shbx: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages recv ALL --to-folder=$(DIR_TMP). --once-only=yes --lock-port=12345 --query=@json:@extend:'{"dropbox_name":"@preset:misc.aoc_shbx_name@","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false}' --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000}'
	@touch $@
$(T)aocp_list_shbx: $(T).exists
	@echo $@
	$(EXE_MAN) aoc packages list --query=@json:@extend:'{"dropbox_name":"@preset:misc.aoc_shbx_name@","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
	@touch $@
taocp: $(T)aocp1 $(T)aocp2 $(T)aocp3 $(T)aocp4 $(T)aocp5 $(T)aocp5 $(T)aocp_send_pub_sh $(T)aocp_send_pub_usr $(T)aocp_send_shbx $(T)aocp_send_sh_meta_long $(T)aocp_send_sh_meta_short $(T)aocp_recv_shbx $(T)aocp_list_shbx
$(T)aocadm1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin auth_providers list
	$(EXE_BEG_FAI) aoc admin subscription$(EXE_END_FAI)
	@touch $@
$(T)aoc8: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace list
	@touch $@
$(T)aoc9: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v3 events
	@touch $@
$(T)aoc11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v3 access_key create @json:'{"id":"testsub1","storage":{"path":"/folder1"}}'
	@touch $@
$(T)aoc12: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret v3 access_key delete testsub1
	@touch $@
$(T)aoc9b: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret browse /
	@touch $@
$(T)aoc10: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret mkdir /folder1
	@touch $@
$(T)aoc13: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource node do %name:@preset:misc.aoc_ak_name --secret=@preset:misc.aoc_ak_secret delete /folder1
	@touch $@
$(T)aoc14: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin resource workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@touch $@
$(T)aoc15: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin analytics transfers --query=@json:'{"status":"completed","direction":"receive"}' --notif-to=@preset:misc.email_external --notif-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
	@touch $@
$(T)aocarself: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin res self show
	$(EXE_MAN) aoc admin res organization show
	$(EXE_MAN) aoc admin res user list
	$(EXE_MAN) aoc admin res user modify @extend:%name:@preset:misc.aoc_user_email@ @json:'{"deactivated":false}'
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
	set -x&&\
	clt_reg_id=$$($(EXE_NOMAN) aoc admin res client_registration_token list --fields=ALL --select=@json:'{"data.name":"test_client_reg1"}' --fields=id --format=csv --display=data|tail -n 1)&&\
	$(EXE_MAN) aoc admin res client_registration_token delete $${clt_reg_id}
	@touch $@
taocadm: $(T)aocadm1 $(T)aoc8 $(T)aoc9 $(T)aoc9b $(T)aoc10 $(T)aoc11 $(T)aoc12 $(T)aoc13 $(T)aoc14 $(T)aoc15 $(T)aocarself $(T)aoccltreg
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
	$(EXE_BEG_IGN) aoc admin ats access_key delete ak1ibmcloud$(EXE_END_IGN)
	$(EXE_BEG_FAI) aoc admin ats access_key create --cloud=softlayer --region=@preset:misc.icos_bucket_region --params=@json:@extend:'{"id":"ak1ibmcloud","secret":"my_secret_here","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:misc.icos_bucket_name@","credentials":{"access_key_id":"@preset:misc.icos_bucket_key@","secret_access_key":"@preset:misc.icos_bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@touch $@
$(T)aocat9: $(T).exists
	@echo $@
	$(EXE_BEG_FAI)aoc admin ats access_key create --cloud=aws --region=@preset:misc.aws_bucket_region --params=@json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:misc.aws_bucket_name@","credentials":{"access_key_id":"@preset:misc.aws_bucket_key@","secret_access_key":"@preset:misc.aws_bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@touch $@
$(T)aocat10: $(T).exists
	@echo $@
	$(EXE_BEG_FAI) aoc admin ats access_key list --fields=name,id$(EXE_END_FAI)
	@touch $@
$(T)aocat11: $(T).exists
	@echo $@
	$(EXE_MAN) aoc admin ats access_key node ak1ibmcloud --secret=my_secret_here browse /
	@touch $@
$(T)aocat13: $(T).exists
	@echo $@
	$(EXE_BEG_FAI) aoc admin ats access_key delete ak1ibmcloud$(EXE_END_FAI)
	@touch $@
taocts: $(T)aocat4 $(T)aocat5 $(T)aocat6 $(T)aocat7 $(T)aocat8 $(T)aocat9 $(T)aocat10 $(T)aocat11 $(T)aocat13
$(DIR_TMP)wf_id.txt: $(T)aocauto1
	$(EXE_MAN) aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data > $@
$(T)aocauto1: $(T).exists
	@echo $@
	$(EXE_MAN) aoc automation workflow create @json:'{"name":"test_workflow"}'
	@touch $@
$(T)aocauto2: $(T).exists
	@echo $@
	$(EXE_MAN) aoc automation workflow list
	$(EXE_MAN) aoc automation workflow list --query=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@touch $@
$(T)aocauto3: $(DIR_TMP)wf_id.txt
	@echo $@
	set -x&&\
	wf_id=$$(cat $(DIR_TMP)wf_id.txt)&&\
	$(EXE_MAN) aoc automation workflow action $${wf_id} create @json:'{"name":"toto"}' \
		| tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info>tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@touch $@
$(T)aocauto10: $(DIR_TMP)wf_id.txt
	@echo $@
	set -x&&\
	wf_id=$$(cat $(DIR_TMP)wf_id.txt)&&\
	$(EXE_MAN) aoc automation workflow delete $${wf_id}
	rm -f $(T)wf.id
	@touch $@
taocauto: $(T)aocauto1 $(T)aocauto2 $(T)aocauto3 $(T)aocauto10
taoc: taocgen taocf taocp taocadm taocts taocauto

$(T)orch_wizard: $(T).exists
	@echo $@
	$(EXE_NOMAN) config detect @preset:tst_orch.url
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_orch.url orchestrator --username=test --password=test
	@touch $@
$(T)orch_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator health
	$(EXE_BEG_ERR) orchestrator health --url=https://wrong.url --format=nagios$(EXE_END_ERR)
	@touch $@
$(T)o2: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator info
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
	$(EXE_MAN) orchestrator workflow start @preset:misc.orch_workflow_id @json:'{"Param":"world !"}'
	@touch $@
$(T)o7: $(T).exists
	@echo $@
	$(EXE_MAN) orchestrator workflow start @preset:misc.orch_workflow_id @json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
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

torc: $(T)orch_wizard $(T)orch_nagios $(T)o2 $(T)o3 $(T)o4 $(T)o5 $(T)o6 $(T)o7 $(T)o8 $(T)o9 $(T)o10

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
	$(EXE_BEG_IGN) ats access_key delete ak2ibmcloud$(EXE_END_IGN)
	$(EXE_BEG_FAI) ats access_key create --cloud=softlayer --region=@preset:misc.icos_bucket_region --params=@json:@extend:'{"id":"ak2ibmcloud","secret":"my_secret_here","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:misc.icos_bucket_name@","credentials":{"access_key_id":"@preset:misc.icos_bucket_key@","secret_access_key":"@preset:misc.icos_bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	$(EXE_MAN) ats access_key entitlement ak2ibmcloud
	$(EXE_MAN) ats access_key show ak2ibmcloud
	@touch $@
$(T)at9: $(T).exists
	@echo $@
	$(EXE_BEG_FAI) ats access_key create --cloud=aws --region=@preset:misc.aws_bucket_region --params=@json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:misc.aws_bucket_name@","credentials":{"access_key_id":"@preset:misc.aws_bucket_key@","secret_access_key":"@preset:misc.aws_bucket_secret@"},"path":"/"}}'$(EXE_END_FAI)
	@touch $@
$(T)at10: $(T).exists
	@echo $@
	$(EXE_BEG_FAI) ats access_key list --fields=name,id$(EXE_END_FAI)
	@touch $@
$(T)at11: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key node ak2ibmcloud browse / --secret=my_secret_here
	@touch $@
$(T)at12: $(T).exists
	@echo $@
	$(EXE_MAN) ats access_key cluster ak2ibmcloud --secret=my_secret_here
	@touch $@
$(T)at13: $(T).exists
	$(EXE_BEG_FAI) ats access_key delete ak2ibmcloud$(EXE_END_FAI)
	@touch $@
$(T)at14: $(T).exists
	@echo $@
	$(EXE_BEG_FAI) ats access_key delete ak_aws$(EXE_END_FAI)
	@touch $@

tats: $(T)at4 $(T)at5 $(T)at6 $(T)at7 $(T)at2 $(T)at1 $(T)at3 $(T)at8 $(T)at9 $(T)at10 $(T)at11 $(T)at12 $(T)at13 $(T)at14

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
$(T)ndsyncv1: $(T).exists
	@echo $@
	rm -fr $(LCL_SYNC_DIR)
	mkdir -p $(LCL_SYNC_DIR)
	$(EXE_MAN) node sync start --sync-info=@json:'{"sessions":[{"name":"my_node_sync1","direction":"pull","local_dir":"$(LCL_SYNC_DIR)","remote_dir":"/aspera-test-dir-tiny","reset":true}]}'
	$(EXE_MAN) node sync admin status --sync-info=@json:'{"sessions":[{"name":"my_node_sync1","direction":"pull","local_dir":"$(LCL_SYNC_DIR)","remote_dir":"/aspera-test-dir-tiny","reset":true}]}'
	@touch $@
$(T)ndsyncv2: $(T).exists
	@echo $@
	rm -fr $(LCL_SYNC_DIR)
	mkdir -p $(LCL_SYNC_DIR)
	$(EXE_MAN) node sync start --sync-info=@json:'{"name":"my_node_sync2","reset":true,"direction":"pull","local":{"path":"$(LCL_SYNC_DIR)"},"remote":{"path":"/aspera-test-dir-tiny"}}'
	$(EXE_MAN) node sync admin status --sync-info=@json:'{"name":"my_node_sync2","reset":true,"direction":"pull","local":{"path":"$(LCL_SYNC_DIR)"},"remote":{"path":"/aspera-test-dir-tiny"}}'
	@touch $@
tnsync: $(T)sy1 $(T)sy2 $(T)sy3 $(T)sy4 $(T)sy5 $(T)ndsyncv1 $(T)ndsyncv2

$(T)sync_create: $(T).exists
	@echo $@
	set -x&&\
	hostport=$$($(EXE_NOMAN) config preset get tst_server url|cut -f3 -d/)&&\
	host=$${hostport%:*}&&\
	port=$${hostport#*:}&&\
	$(EXE_MAN) node ssync create @json:@extend:'{"configuration":{"name":"my_node_sync","local":{"path":"@preset:sync.local_path@"},"remote":{"host":"'"$${host}"'","port":'"$${port}"',"user":"@preset:tst_server.username@","pass":"@preset:tst_server.password@","path":"@preset:sync.remote_path@"}}}'
	$(EXE_MAN) node ssync list
	@touch $@
$(T)sync_other: $(T)sync_create
	@echo $@
	$(EXE_MAN) node ssync start %name:my_node_sync
	$(EXE_MAN) node ssync show %name:my_node_sync
	$(EXE_MAN) node ssync bandwidth %name:my_node_sync
	$(EXE_MAN) node ssync counters %name:my_node_sync
	$(EXE_MAN) node ssync files %name:my_node_sync
	$(EXE_MAN) node ssync state %name:my_node_sync
	$(EXE_MAN) node ssync stop %name:my_node_sync
	$(EXE_MAN) node ssync summary %name:my_node_sync
	$(EXE_MAN) node ssync delete %name:my_node_sync
	@touch $@
tnsyncs: $(T)sync_create $(T)sync_other

clean::
	rm -f $(TEST_CONFIG)

$(T)conf_ascp_1: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp show
	$(EXE_MAN) config ascp spec
	$(EXE_MAN) config ascp errors
	@touch $@
$(T)conf_ascp_2: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp products list
	$(EXE_MAN) $(TMP_CONF) config ascp products use 'Aspera Connect'
	$(EXE_MAN) $(TMP_CONF) config ascp use /usr/bin/ascp
	@touch $@
$(T)conf_ascp_3: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect list
	@touch $@
$(T)conf_ascp_4: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect info 'Aspera Connect for Windows'
	@touch $@
$(T)conf_ascp_5: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' list
	@touch $@
$(T)conf_ascp_6: $(T).exists
	@echo $@
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' download 'Windows Installer' --to-folder=$(DIR_TMP).
	$(EXE_MAN) config ascp connect version 'Aspera Connect for Windows' open documentation
	@touch $@
$(T)conf_ascp_7: $(T).exists
	@echo $@
	rm -fr $(HOME)/.aspera/sdk
	$(EXE_MAN) config ascp install
	rm -fr $(T)sdk_test_dir
	$(EXE_MAN) config ascp install --sdk-folder=$(T)sdk_test_dir
	@touch $@
$(T)conf_ascp_8: $(T)conf_ascp_7
	@echo $@
	$(EXE_MAN) config ascp info --sdk-folder=$(T)sdk_test_dir
	@touch $@
$(T)conf_pset_1: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset set conf_name param value
	$(EXE_MAN) $(TMP_CONF) config preset unset conf_name param
	$(EXE_NOMAN) config preset lookup --url=@preset:tst_faspex4.url --username=@preset:tst_faspex4.username
	@touch $@
$(T)conf_pset_2: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset show conf_name
	@touch $@
$(T)conf_pset_3: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset set default shares conf_name
	@touch $@
$(T)conf_pset_4: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset delete conf_name
	@touch $@
$(T)conf_pset_5: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset initialize conf_name @json:'{"p1":"v1","p2":"v2"}'
	@touch $@
$(T)conf_pset_6: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset update conf_name --p1=v1 --p2=v2
	@touch $@
$(T)conf_open: $(T).exists
	@echo $@ open configuration file in text editor
	$(EXE_MAN) $(TMP_CONF) config open
	@touch $@
$(T)conf_list: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset list
	@touch $@
$(T)conf_over: $(T).exists
	@echo $@
	$(EXE_MAN) $(TMP_CONF) config preset overview
	@touch $@
$(T)conf_gem: $(T).exists
	@echo $@
	$(EXE_MAN) config gem path
	$(EXE_MAN) config gem version
	$(EXE_MAN) config gem name
	$(EXE_MAN) config folder
	$(EXE_MAN) $(TMP_CONF) config initdemo
	$(EXE_NOMAN) $(TMP_CONF) config initdemo
	@touch $@
$(T)conf_vault: $(T).exists
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
	@touch $@
$(T)conf_help: $(T).exists
	@echo $@
	$(EXE_NOMAN) -h
	$(EXE_NOMAN) --bash-comp
	$(EXE_MAN) config coffee
	$(EXE_MAN) config coffee --ui=text
	env -u TERM_PROGRAM -u LC_TERMINAL $(EXE_NOMAN) config coffee --ui=text
	@touch $@
$(T)conf_plugins: $(T).exists
	@echo $@
	$(EXE_MAN) config plugin list
	$(EXE_MAN) config plugin create mycommand $(T)
	$(EXE_NOMAN) mycommand --plugin-folder=$(T)
	@touch $@
$(T)conf_wizard_org: $(T).exists
	@echo $@
	$(EXE_MAN) config flush_tokens
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:misc.aoc_org aoc --pkeypath= --username=@preset:misc.aoc_user_email --use-generic-client=yes
	@touch $@
$(T)conf_wizard_gen: $(T).exists
	@echo $@
	$(EXE_MAN) config flush_tokens
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:misc.aoc_org aoc --pkeypath= --username=@preset:misc.aoc_user_email
	@touch $@
$(T)conf_detect: $(T).exists
	@echo $@
	$(EXE_MAN) config detect @preset:misc.aoc_org aoc
	$(EXE_MAN) config detect @preset:tst_faspex4.url
	$(EXE_MAN) config detect @preset:tst_node_simple.url
	@touch $@
$(T)conf_genkey: $(T).exists
	@echo $@
	rm -f $(DIR_TMP)mykey $(DIR_TMP)mykey.pub
	$(EXE_MAN) config genkey $(DIR_TMP)mykey
	rm -f $(DIR_TMP)mykey $(DIR_TMP)mykey.pub
	$(EXE_MAN) config genkey $(DIR_TMP)mykey 4096
	$(EXE_BEG_ERR) config genkey $(DIR_TMP)mykey not_int$(EXE_END_ERR)
	@touch $@
$(T)conf_smtp: $(T).exists
	@echo $@
	$(EXE_MAN) config email_test --notif-to=@preset:misc.email_external
	@touch $@
$(T)conf_pac: $(T).exists
	@echo $@
	$(EXE_MAN) config proxy_check --fpac=@file:$(DIR_TOP)examples/proxy.pac https://eudemo.asperademo.com --proxy-credentials=@list:,user,pass
	@touch $@
$(T)conf_check_gem: $(T).exists
	@echo $@
	$(EXE_MAN) config check_update
	rm -f $(HOME)/.aspera/ascli/persist_store/version_last_check.txt
	$(EXE_MAN) config check_update
	@touch $@
$(T)conf_doc: $(T).exists
	@echo $@
	$(EXE_MAN) config doc
	$(EXE_MAN) config doc transfer-parameters
	@touch $@
$(T)conf_echo: $(T).exists
	@echo $@
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
	@touch $@
$(T)conf_interactive: $(T).exists
	@echo $@
	$(EXE_MAN) config echo @secret:
	@touch $@
$(T)conf_hint: $(T).exists
	@echo $@
	$(EXE_BEG_ERR) config hint Aspera::Fasp::Error 'Remote host is not who we expected'$(EXE_END_ERR)
	$(EXE_BEG_ERR) config hint OpenSSL::SSL::SSLError 'does not match the server certificate'$(EXE_END_ERR)
	$(EXE_BEG_ERR) config hint Aspera::RestCallError 'Signature has expired'$(EXE_END_ERR)
	$(EXE_BEG_ERR) config hint OpenSSL::PKey::RSAError 'Neither PUB key nor PRIV key'$(EXE_END_ERR)
	@touch $@
tconfig: $(T)conf_ascp_1 $(T)conf_ascp_2 $(T)conf_ascp_3 $(T)conf_ascp_4 $(T)conf_ascp_5 $(T)conf_ascp_6 $(T)conf_ascp_7 $(T)conf_ascp_8 $(T)conf_pset_1 $(T)conf_pset_2 $(T)conf_pset_3 $(T)conf_pset_4 $(T)conf_pset_5 $(T)conf_pset_6 $(T)conf_open $(T)conf_list $(T)conf_over $(T)conf_gem $(T)conf_vault $(T)conf_help $(T)conf_plugins $(T)conf_wizard_org $(T)conf_wizard_gen $(T)conf_detect $(T)conf_genkey $(T)conf_smtp $(T)conf_pac $(T)conf_check_gem $(T)conf_doc $(T)conf_echo $(T)conf_hint

$(T)prev_check: $(T).exists
	@echo $@
	$(EXE_MAN) preview check --skip-types=office
	@touch $@
$(T)prev_dcm: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --base=$@ @preset:misc.file_dcm
	@touch $@
$(T)prev_pdf: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_pdf
	@touch $@
$(T)prev_docx: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_docx
	@touch $@
$(T)prev_mxf_blend: $(T).exists
	@echo $@
	$(EXE_MAN) preview test --base=$@ @preset:misc.file_mxf mp4 --video-conversion=blend --query=@json:'{"text":true,"double":true}'
	@touch $@
$(T)prev_mpg_png_fix: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_mpg --video-png-conv=fixed
	@touch $@
$(T)prev_mpg_png_ani: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_mpg --video-png-conv=animated
	@touch $@
$(T)prev_mpg_reencode: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_mpg mp4 --video-conversion=reencode
	@touch $@
$(T)prev_mpg_clips: $(T).exists
	@echo $@
	$(EXE_MAN) preview show --base=$@ @preset:misc.file_mpg mp4 --video-conversion=clips
	@touch $@
$(T)prev_events: $(T).exists
	@echo $@
	$(EXE_NOMAN) -Ptst_ak_preview node upload @preset:misc.file_mxf @preset:misc.file_docx --ts=@json:'{"target_rate_kbps":1000000}'
	sleep 4
	$(EXE_MAN) preview trevents --once-only=yes --skip-types=office --log-level=info
	@touch $@
$(T)prev_scan: $(T).exists
	@echo $@
	$(EXE_MAN) preview scan --skip-types=office --log-level=info
	@touch $@
$(T)prev_folder: $(T).exists
	@echo $@
	$(EXE_MAN) preview scan --scan-id=1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
	@touch $@

tprev: $(T)prev_check $(T)prev_dcm $(T)prev_pdf $(T)prev_docx $(T)prev_mpg_png_fix $(T)prev_mpg_png_ani $(T)prev_mxf_blend $(T)prev_mpg_reencode $(T)prev_mpg_clips $(T)prev_events $(T)prev_scan $(T)prev_folder
# TODO : finalize
thot:
	rm -fr source_hot
	mkdir source_hot
	$(EXE_BEG_IGN) server delete @extend:@preset:misc.upload_folder@/target_hot$(EXE_END_IGN)
	$(EXE_MAN) server mkdir @extend:@preset:misc.upload_folder@/target_hot
	echo hello > source_hot/newfile
	$(EXE_MAN) server upload --to-folder=@extend:@preset:misc.upload_folder@/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse @extend:@preset:misc.upload_folder@/target_hot
	ls -al source_hot
	sleep 10
	$(EXE_MAN) server upload --to-folder=@extend:@preset:misc.upload_folder@/target_hot --lock-port=12345 --ts=@json:'{"EX_ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(EXE_MAN) server browse @extend:@preset:misc.upload_folder@/target_hot
	ls -al source_hot
	rm -fr source_hot
	@touch $@

$(T)tcos: $(T).exists
	@echo $@
	$(EXE_MAN) cos -N --bucket=@preset:misc.icos_bucket_name --region=@preset:misc.icos_bucket_region --service-credentials=@json:@file:$(DIR_PRIV)service_creds.json node info
	$(EXE_MAN) cos -N --bucket=@preset:misc.icos_bucket_name --endpoint=@preset:misc.icos_bucket_endpoint --apikey=@preset:misc.icos_bucket_apikey --crn=@preset:misc.icos_resource_instance_id node info
	$(EXE_MAN) cos node info
	$(EXE_MAN) cos node access_key show self
	$(EXE_MAN) cos node upload $(LCL_TST_ASC_FILEPATH)
	$(EXE_MAN) cos node download $(LCL_TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	@touch $@
tcos: $(T)tcos

$(T)f5_nagios: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 health
	$(EXE_BEG_ERR) faspex5 health --url=https://wrong.example --format=nagios$(EXE_END_ERR)
	@touch $@
$(T)f5_p1: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 packages receive INIT --once-only=yes
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":[{"name":"@preset:tst_faspex5_jwt.username@"}]@preset:misc.faspex5_meta@}' $(LCL_TST_ASC_FILEPATH) --ts=@json:'{"content_protection_password":"my_passphrase_here"}'
	@touch $@
$(T)f5_p2: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 packages list --query=@json:'{"mailbox":"inbox","state":["released"]}'
	@touch $@
$(T)f5_p3: $(T).exists
	@echo $@
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --query=@json:'{"mailbox":"inbox","state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages status "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive "$${package_id}" --to-folder=$(DIR_TMP).  --ts=@json:'{"content_protection_password":"abc123_yo"}'
	$(EXE_MAN) faspex5 packages receive ALL --once-only=yes --to-folder=$(DIR_TMP).
	@touch $@
$(T)f5_pack_shbox: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:misc.faspex5_shinbox@"],"metadata":{"Options":"Opt1","TextInput":"example text"}}' $(LCL_TST_ASC_FILEPATH)
	$(EXE_MAN) faspex5 packages list --box=@preset:misc.faspex5_shinbox
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --box=@preset:misc.faspex5_shinbox --query=@json:'{"state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show --box=@preset:misc.faspex5_shinbox "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive --box=@preset:misc.faspex5_shinbox "$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@
$(T)f5_pack_wrkgrp: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:misc.faspex5_workgroup@"]}' $(LCL_TST_ASC_FILEPATH)
	$(EXE_MAN) faspex5 packages list --box=@preset:misc.faspex5_workgroup --group-type=workgroups
	set -x&&\
	package_id=$$($(EXE_NOMAN) faspex5 packages list --box=@preset:misc.faspex5_workgroup --group-type=workgroups --query=@json:'{"state":["released"],"limit":1,"max":1}' --fields=id --format=csv --display=data)&&\
	$(EXE_MAN) faspex5 packages show --box=@preset:misc.faspex5_workgroup --group-type=workgroups "$${package_id}"&&\
	$(EXE_MAN) faspex5 packages receive --box=@preset:misc.faspex5_workgroup --group-type=workgroups "$${package_id}" --to-folder=$(DIR_TMP).
	@touch $@
$(T)f5_sh_fold: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 shared list
	$(EXE_MAN) faspex5 shared browse %name:@preset:misc.faspex_src
	@touch $@
$(T)f5_user_res: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 bearer_token
	$(EXE_MAN) faspex5 admin res contacts list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res shared_inboxes list
	$(EXE_MAN) faspex5 admin res shared_inboxes members %name:'ascli shinbox' list
	$(EXE_MAN) faspex5 admin res workgroups list
	$(EXE_MAN) faspex5 admin res saml_configs list
	$(EXE_MAN) faspex5 admin res metadata_profiles list
	@touch $@
$(T)f5_adm: $(T).exists
	@echo $@
	$(EXE_MAN) -Pf5_admin faspex5 admin res accounts list
	$(EXE_MAN) -Pf5_admin faspex5 admin res jobs list
	$(EXE_MAN) -Pf5_admin faspex5 admin res node list 
	$(EXE_MAN) -Pf5_admin faspex5 admin res oauth_clients list
	$(EXE_MAN) -Pf5_admin faspex5 admin res registrations list
	$(EXE_MAN) -Pf5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' create %name:john@example.com
	$(EXE_MAN) -Pf5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' delete %name:john@example.com
	$(EXE_MAN) -Pf5_admin faspex5 admin res shared_inboxes invite %name:'ascli shinbox' johnny@example.com
	$(EXE_MAN) -Pf5_admin faspex5 admin res shared_inboxes members %name:'ascli shinbox' delete %name:johnny@example.com
	$(EXE_MAN) -Pf5_admin faspex5 admin smtp show
	$(EXE_MAN) -Pf5_admin faspex5 admin smtp test @preset:misc.email_external
	@touch $@
$(T)f5_user: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 user profile show
	$(EXE_MAN) faspex5 user profile modify @json:'{"preference":{"connect_disabled":false}}'
	@touch $@
$(T)f5_error: $(T).exists
	@echo $@
	$(EXE_NOMAN) faspex5 health --url=wrong
	@touch $@
$(T)f5_webauth: $(T).exists
	@echo $@
	$(EXE_NOMAN) -Pf5_web faspex5 version
	@touch $@
$(T)f5_wizard: $(T).exists
	@echo $@
	$(EXE_MAN) config wizard $(WIZ_TEST) @preset:tst_faspex5_jwt.url faspex5 --pkeypath=@preset:tst_server_bykey.ssh_keys -Ptst_faspex5_jwt
	$(EXE_BEG_ERR) config detect https://eudemo.asperademo.com:22 faspex5$(EXE_END_ERR)
	$(EXE_MAN) -N config detect @preset:tst_faspex5_jwt.url
	$(EXE_NOMAN) config detect @preset:tst_faspex5_jwt.url
	@touch $@
$(T)f5_fxgw: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 gateway https://localhost:12345/aspera/faspex &\
		jobs -p > $(T)server_pid
	sleep 2
	$(EXE_NOMAN) -N faspex --url=https://localhost:12345/aspera/faspex --username=_unused_ --password=_unused_ --insecure=yes package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway faspex 5"}' 'faux:///test1?1m'
	sleep 3
	kill -USR1 $$(cat $(T)server_pid)
	@touch $@
$(T)f5_postproc: $(T).exists
	@echo $@
	$(EXE_MAN) faspex5 postprocessing @json:'{"url":"https://localhost:8443/domain","processing":{"script_folder":"tests"},"certificate":{"key":"../local/k","cert":"../local/c","chain":"../local/ch"}}' &\
	jobs -p > $(T)server_pid
	sleep 10
	kill -INT $$(cat $(T)server_pid)
	@touch $@

tf5: $(T)f5_nagios $(T)f5_p1 $(T)f5_p2 $(T)f5_p3 $(T)f5_pack_shbox $(T)f5_pack_wrkgrp $(T)f5_user_res $(T)f5_adm $(T)f5_user $(T)f5_error $(T)f5_wizard $(T)f5_fxgw $(T)f5_sh_fold

