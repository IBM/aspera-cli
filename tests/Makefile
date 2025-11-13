##################################
# Integration tests

# cspell:ignore INCMAN Pjns Ptst noded

# root folder is one level up
DIR_TOP=../

include $(DIR_TOP)common.mak

# configuration file used for tests, template is generated in "docs"
# this is the actual conf file, create your own from template located in "docs"
ifndef ASPERA_CLI_TEST_CONF_FILE
$(error ASPERA_CLI_TEST_CONF_FILE is not set. Refer to CONTRIBUTING.md.)
endif

# macros to define a test suite
# defines targets: $(1), skip_$(1)
define test_suite
$(1): $(2)
skip_$(1):
	@make $(TMP_EXISTS)
	touch $(2)
clean_$(1):
	rm -f $(2)
list::
	@echo "$(1)"
.PHONY: $(1) skip_$(1) clean_$(1)
endef

# same as previous, but adds to target: all
define test_suite_all
all:: $(2)
$(eval $(call test_suite,$(1),$(2)))
endef

# folder where flag files for tests are generated:
# use this folder only for those flags, as it is used for progress bar
F=$(DIR_TMP)t/
# Store state values, like identifiers
STATE=$(DIR_TMP)state/
# flag to check if tmp folder exists
TMP_EXISTS=$(F).exists

skip:
	@if test -z "$(T)"; then echo "Usage:\nmake $@ T=<case identifier>\n"; exit 1; fi
	@mkdir -p $(F)
	@echo "Skipping test: $(T)"
	@touch $(F)$(T)
reset:
	@if test -z "$(T)"; then echo "Usage:\nmake $@ T=<case identifier>\n"; exit 1; fi
	@echo "Resetting test: $(T)"
	@rm -f $(F)$(T)

# test group: principal
all:: $(DIR_TOP).gems_checked

# test group: require user interaction
interactive: $(F)f5_webauth $(F)aoc_webauth $(F)conf_interactive $(F)conf_vault_macos

use_rmagick: optional_gems $(F)aoc_file_id_10 $(F)aoc_file_id_11 $(F)aoc_file_id_12 $(F)conf_coffee_3 $(F)conf_image
use_grpc: optional_gems $(F)serv_upload4
use_mimemagic: optional_gems $(F)prev_dcm_mm $(F)prev_jpg_unk_mm 
use_sym_encryption: optional_gems $(F)conf_vault_file

# test group: require optional gems
optional: use_rmagick use_grpc use_mimemagic use_sym_encryption

optional_gems:
	cd $(DIR_TOP) && make install_optional_gems
# all tests, including interactive ones
full: all optional interactive

# just to test nagios, but those are tested in the respective plugins
only_health: $(F)f4_health $(F)shares_health $(F)cons_health $(F)f5_health $(F)serv_health_xfer_nagios $(F)nd_health

only_sync_local: $(F)serv_sync_pull_args $(F)serv_sync_pull_conf $(F)aoc_sync_pull_conf_parms $(F)aoc_sync_conf_pull_params $(F)shares_sync

only_sync: tnsync tnsyncs only_sync_local

only_progress: $(F)serv_upload1 $(F)serv_upload3

.PHONY: interactive use_rmagick use_grpc use_mimemagic use_sym_encryption optional optional_gems full only_health only_sync only_progress

# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
DIR_CONNECT_DOWNLOAD=$(HOME)/Downloads/
# package title for faspex and aoc
PACKAGE_TITLE_BASE=$(CLI_NAME) test $(shell LANG=C date)
# override $HOME/.aspera/ascli
CLI_HOME=$(DIR_TMP)$(CLI_NAME)_home/
# give waring and stop on first warning in this gem code
RUBY_WARN=ruby -w $(DIR_TST)warning_exit_wrapper.rb
# CLI with default config file
CLI_NOCONF=$(RUBY_WARN) $(CLI_PATH) --home=$(CLI_HOME)
# "CLI_TEST" is used to call the tool in the testing environment
CLI_TEST=$(CLI_NOCONF) --config-file=$(ASPERA_CLI_TEST_CONF_FILE)
# JRuby does not support some encryptions
ifneq (,$(findstring jruby,$(shell ruby -v)))
CLI_TEST+= -Pjns
endif
# temp configuration file that is modified, to avoid changing the main configuration file
TEST_CONFIG=$(DIR_TMP)sample.conf
# Do not include TEST_CONFIG, because it's changing and would trigger re-test
WIZ_DEPS=
# "CLI_TMP_CONF" is used for commands that modify the config file
CLI_TMP_CONF=$(CLI_NOCONF) --config-file=$(TEST_CONFIG)
CLI_WIZ_TEST=ASCLI_WIZ_TEST=yes $(CLI_TMP_CONF)
# "INCMAN" is a tag used to generate sample commands in documentation (see in docs/Makefile)
INCMAN=
# exec begin error: enclose tests that shall result in error
BEG_ERR=if 
# expect error, show error
END_ERR_SHOW=;then echo "No error: problem";exit 1;else echo "Test ok (Error is expected)";fi
END_ERR_HIDE=>/dev/null 2>&1$(END_ERR_SHOW)
# enclose tests that fail, but should not
BEG_FAI=if 
END_FAI_SHOW=;then echo "TODO: test worked, restore test?";exit 1;else echo "Test known to fail";fi
END_FAI_HIDE=>/dev/null 2>&1$(END_FAI_SHOW)
# enclose tests whose status is ignored, mainly optional cleanups, for restarts
BEG_IGN=
END_IGN=>/dev/null 2>&1 || true
# simple command line to percent-encode
URL_ENCODER=ruby -r uri -e 'puts URI.encode_www_form_component(ARGV.first)'
# testing file generated locally (special shell characters must be escaped for shell, special makefile characters escaped)
TST_ASC_FILENAME=data_file.bin
TST_ASC_LCL_PATH=$(DIR_TMP)$(TST_ASC_FILENAME)
# This file name contains special characters, it must be quoted when used in shell
# cspell:disable-next-line
TST_UTF_FILENAME=𒐫spécial{\#😀تツ
TST_UTF_LCL_PATH=$(DIR_TMP)$(TST_UTF_FILENAME)
# a medium sized file for testing
TST_MED_FILENAME=$(TST_UTF_FILENAME)
# needs to be quoted, as there is shell special character: "?"
TST_MED_LCL_PATH=faux:///$(shell $(URL_ENCODER) "$(TST_MED_FILENAME)")?100m
TEMPORIZE_CREATE=sleep 10
TEMPORIZE_FILE=sleep 30

# sync dir must be an absolute path, but tmp dir may not exist yet, while its enclosing folder should exist
TMP_SYNCS=$(shell realpath $$(dirname $(DIR_TMP)))/$(shell basename $(DIR_TMP))/syncs/

SYNC_NAME=my_sync_session

ifdef ASPERA_CLI_TEST_MACOS
all:: $(F).ssh_ok
# ensure SSH is enabled on macos only
$(F).ssh_ok: $(TMP_EXISTS)
	sudo systemsetup -getremotelogin | grep -s Off && sudo systemsetup -setremotelogin on || :
	sudo systemsetup -getremotelogin
	sudo -u asperadaemon test -w /Library/Logs/Aspera || sudo chown -R asperadaemon: /Library/Logs/Aspera
	sudo -u asperadaemon test -w /Library/Logs/Aspera
	sudo -u asperadaemon ls -al /Library/Logs/Aspera
	make restart_noded
	while ! $(CLI_TEST) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
	touch $@
clean_local:
	rm -f $(F).ssh_ok
clean:: clean_local
restart_noded:
	sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperalee.plist
	sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperanoded.plist
	sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperaredisd.plist
	sleep 5
	sudo /bin/chmod +a "asperadaemon allow read,write,delete,add_file" /Library/Logs/Aspera
	-ps -ef|grep aspera|grep -v grep
	sudo launchctl load /Library/LaunchDaemons/com.aspera.asperaredisd.plist
	sudo launchctl load /Library/LaunchDaemons/com.aspera.asperanoded.plist
	sleep 5
	-ps -ef|grep aspera|grep -v grep
endif

START_TEST=$(DIR_TST)mark begin
STOP_TEST=$(DIR_TST)mark end

###########
# Coverage
clean::
	rm -fr $(DIR_TOP)coverage
	rm -f $(DIR_TOP)simplecov.log

###########
# Tests
# all test cases depend on this
$(TMP_EXISTS):
	mkdir -p $(F)
	mkdir -p $(STATE)
	echo 'This is a small test file' > $(TST_ASC_LCL_PATH)
	echo 'This is a small test file' > "$(TST_UTF_LCL_PATH)"
	cp $(ASPERA_CLI_TEST_CONF_FILE) $(TEST_CONFIG)
	touch $(TMP_EXISTS)
$(TEST_CONFIG): $(TMP_EXISTS)
	cp $(ASPERA_CLI_TEST_CONF_FILE) $(TEST_CONFIG)
clean::
	rm -fr $(F) $(STATE)
	rm -f $(TST_ASC_LCL_PATH) "$(TST_UTF_LCL_PATH)"
	rm -f $(TEST_CONFIG)
	rm -f $(DIR_TOP).rspec_status
#######################################################################################################################
$(F)unit: $(TMP_EXISTS)
	@$(START_TEST) $@
	bundle exec rake spec
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tunit,$(F)unit))
#######################################################################################################################
$(F)shares_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares health
	@$(STOP_TEST) $@
$(F)shares_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) shares health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(F)shares_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:shares_admin.url shares
	@$(STOP_TEST) $@
$(F)shares_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:shares_admin.url shares --username=test --password=test
	@$(STOP_TEST) $@
$(F)shares_admin_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin node list
	@$(STOP_TEST) $@
$(F)shares_admin_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin group all list
	@$(STOP_TEST) $@
$(F)shares_admin_3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user all list
	@$(STOP_TEST) $@
$(F)shares_admin_4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user local list
	@$(STOP_TEST) $@
$(F)shares_admin_5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user all app_authorizations %username:@preset:shares_admin.username show
	@$(STOP_TEST) $@
$(F)shares_admin_6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user all app_authorizations %username:@preset:shares_admin.username modify @json:'{"app_login":true}'
	@$(STOP_TEST) $@
$(F)shares_admin_7: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user all share_permissions %username:@preset:shares_admin.username list
	@$(STOP_TEST) $@
$(F)shares_admin_8: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user all share_permissions %username:@preset:shares_admin.username show %name:@preset:shares.share
	@$(STOP_TEST) $@
$(F)shares_admin_9: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin user saml import @json:'{"id":"the_id","name_id":"the_name"}'
	@$(STOP_TEST) $@
$(F)shares_admin_10: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) shares admin user ldap add the_name$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)shares_admin_11: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin share list --fields=DEF,-status,status_message
	@$(STOP_TEST) $@
$(F)shares_admin_12: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares admin share user_permissions %name:@preset:shares.share list
	@$(STOP_TEST) $@
$(F)shares_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files browse /
	@$(STOP_TEST) $@
$(F)shares_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files upload --to-folder=@preset:shares.share_folder $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)shares_3: $(F)shares_2
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files download --to-folder=$(DIR_TMP). @extend:@preset:shares.share_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)shares_4: $(F)shares_3
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files delete @extend:@preset:shares.share_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)shares_5: $(F)shares_4
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files upload --to-folder=@preset:shares.share_folder $(TST_ASC_LCL_PATH) --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"@preset:tst_httpgw.url@"}'
	@$(STOP_TEST) $@
$(F)shares_6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files upload --to-folder=@preset:shares.share_folder 'faux:///testfile?1m' --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"@preset:tst_httpgw.url@","synchronous":true,"api_version":"v1","upload_chunk_size":100000}'
	@$(STOP_TEST) $@
$(F)shares_6bis: $(TMP_EXISTS)
	@$(START_TEST) $@
	mkdir -p $(DIR_TMP)sendfolder/sub
	touch $(DIR_TMP)sendfolder/{1,2,3,sub/1,sub/2}
	$(INCMAN)$(CLI_TEST) shares files upload --to-folder=@preset:shares.share_folder $(DIR_TMP)sendfolder --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"@preset:tst_httpgw.url@","synchronous":true,"api_version":"v1","upload_chunk_size":100000}'
	@$(STOP_TEST) $@
$(F)shares_7: $(F)shares_5
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files download --to-folder=$(DIR_TMP). @extend:@preset:shares.share_folder@/$(TST_ASC_FILENAME) @extend:@preset:shares.share_folder@/$(TST_ASC_FILENAME) --transfer=httpgw --preset=no_wss --transfer-info=@json:@extend:'{"url":"@preset:tst_httpgw.url@"}'
	@$(STOP_TEST) $@
$(F)shares_8: $(F)shares_7
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files delete @extend:@preset:shares.share_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)shares_9: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) shares files delete @extend:@preset:shares.share_folder@/new_folder$(END_IGN)
	$(INCMAN)$(CLI_TEST) shares files mkdir @extend:@preset:shares.share_folder@/new_folder
	@$(STOP_TEST) $@
$(F)shares_10: $(F)shares_9
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) shares files delete @extend:@preset:shares.share_folder@/new_folder
	@$(STOP_TEST) $@
$(F)shares_sync: $(TMP_EXISTS)
	@$(START_TEST) $@
	mkdir -p $(TMP_SYNCS)shares_sync
	$(BEG_IGN)$(CLI_TEST) shares files mkdir @extend:@preset:shares.share_folder@/synctst$(END_IGN)
	echo "Some sample file" > $(TMP_SYNCS)shares_sync/sample_file.txt
	$(INCMAN)$(CLI_TEST) shares files sync push $(TMP_SYNCS)shares_sync --to-folder=@extend:@preset:shares.share_folder@/synctst @json:'{"reset":true}'
	$(INCMAN)$(CLI_TEST) shares files sync push $(TMP_SYNCS)shares_sync --to-folder=@extend:@preset:shares.share_folder@/synctst
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tshares,$(F)shares_health $(F)shares_health_bad $(F)shares_detect $(F)shares_wizard $(F)shares_admin_1 $(F)shares_admin_2 $(F)shares_admin_3 $(F)shares_admin_4 $(F)shares_admin_5 $(F)shares_admin_6 $(F)shares_admin_7 $(F)shares_admin_8 $(F)shares_admin_9 $(F)shares_admin_10 $(F)shares_admin_11 $(F)shares_admin_12 $(F)shares_1 $(F)shares_2 $(F)shares_3 $(F)shares_4 $(F)shares_5 $(F)shares_6 $(F)shares_6bis $(F)shares_7 $(F)shares_8 $(F)shares_9 $(F)shares_10 $(F)shares_sync))
#######################################################################################################################
$(F)serv_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server health transfer --to-folder=@preset:server.upload_folder
	@$(STOP_TEST) $@
$(F)serv_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) server health transfer --url=ssh://wrong.example.com
	@$(STOP_TEST) $@
$(F)serv_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:server_user.url server
	@$(STOP_TEST) $@
$(F)serv_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:server_user.url server --username=@preset:server_user.username --password=@preset:server_user.password
	$(CLI_WIZ_TEST) config wizard @preset:server.address server srv2 --username=@preset:server_user.username --password=@preset:server_user.password
	@$(STOP_TEST) $@
$(F)serv_browse: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server browse /
	@$(STOP_TEST) $@
$(F)serv_mkdir: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server mkdir @preset:server.inside_folder --logger=stdout
	@$(STOP_TEST) $@
$(F)serv_error: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(CLI_TEST) server -Pserver2_user --password=wrong upload $(TST_ASC_LCL_PATH) --transfer-info=@json:'{"monitor":false,"resume":{"iter_max":0}}'$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TEST) server -Pserver2_user --password=wrong browse / --ssh-options=@json:'{"number_of_password_prompts":0}'$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TEST) server -N --url=foo:// ls .$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TEST) server -N --url=@preset:node_user.url upload wrong --ts=@json:'{"token":"test"}' --transfer-info=@json:'{"resume":{"iter_max":0}}'$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TEST) server -N --url=@preset:node_user.url upload wrong --transfer-info=@json:'{"resume":{"iter_max":0}}'$(END_ERR_HIDE)
	$(CLI_TEST) server -N --url=local:// ls .
	@$(STOP_TEST) $@
$(F)serv_upload1: $(F)serv_mkdir 
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload '$(TST_MED_LCL_PATH)' --to-folder=@preset:server.inside_folder --ts=@json:'{"multi_session":3,"multi_session_threshold":1,"resume_policy":"none","target_rate_kbps":100000}' --transfer-info=@json:'{"spawn_delay_sec":2.5,"multi_incr_udp":false}' --progress-bar=yes
	$(INCMAN)$(CLI_TEST) server browse @extend:@preset:server.inside_folder@/$(TST_MED_FILENAME)
	@$(STOP_TEST) $@
$(F)serv_upload2: $(F)serv_mkdir 
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload --src-type=pair '$(TST_MED_LCL_PATH)' @extend:@preset:server.inside_folder@/other_name_2 --notify-to=@preset:misc.email_external --transfer-info=@json:'{"ascp_args":["-l","100m"]}'
	@$(STOP_TEST) $@
$(F)serv_upload3: $(F)serv_mkdir 
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) server delete @extend:@preset:server.inside_folder@/other_name_3$(END_IGN)
	$(INCMAN)$(CLI_TEST) server upload --src-type=pair --sources=@json:@extend:'["$(TST_ASC_LCL_PATH)","@preset:server.inside_folder@/other_name_3"]' --transfer-info.quiet=false --progress=no
	@$(STOP_TEST) $@
$(F)serv_upload4: $(F)serv_mkdir 
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload --sources=@ts --ts=@json:@extend:'{"paths":[{"source":"$(TST_ASC_LCL_PATH)","destination":"@preset:server.inside_folder@/other_name_4"}]}' --transfer=transferd
	@$(STOP_TEST) $@
$(F)serv_upload5: $(F)serv_mkdir 
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload --src-type=pair $(TST_ASC_LCL_PATH) @extend:@preset:server.upload_folder@/other_name_5 --ts=@json:'{"cipher":"aes-192-gcm","content_protection":"encrypt","content_protection_password":"my_secret_here","cookie":"biscuit","create_dir":true,"delete_before_transfer":false,"delete_source":false,"exclude_newer_than":"-1","exclude_older_than":"-10000","fasp_port":33001,"http_fallback":false,"multi_session":0,"overwrite":"diff+older","precalculate_job_size":true,"preserve_access_time":true,"preserve_creation_time":true,"rate_policy":"fair","resume_policy":"sparse_csum","symlink_policy":"follow"}'
	@$(STOP_TEST) $@
$(F)serv_sync_pull_args: $(F)serv_upload1 $(F)serv_upload2 $(F)serv_upload3 $(F)serv_upload5
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)serv_sync_pull_args
	mkdir -p $(TMP_SYNCS)serv_sync_pull_args
	$(CLI_TEST) server sync pull @preset:server.inside_folder --to-folder=$(TMP_SYNCS)serv_sync_pull_args @json:@extend:'{"instance":{"quiet":false},"sessions":[{"name":"serv_sync_pull_args","target_rate":"@preset:sync.bps@","reset":true}]}'
	$(CLI_TEST) server sync admin status $(TMP_SYNCS)serv_sync_pull_args @json:'{"sessions":[{"name":"serv_sync_pull_args"}]}'
	$(CLI_TEST) server sync admin meta $(TMP_SYNCS)serv_sync_pull_args @json:'{"sessions":[{"name":"serv_sync_pull_args"}]}'
	$(CLI_TEST) config sync admin counters $(TMP_SYNCS)serv_sync_pull_args @json:'{"sessions":[{"name":"serv_sync_pull_args"}]}'
	@$(STOP_TEST) $@
$(F)serv_sync_pull_conf: $(F)serv_sync_pull_args
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)serv_sync_pull_conf
	mkdir -p $(TMP_SYNCS)serv_sync_pull_conf
	$(CLI_TEST) server sync pull @preset:server.inside_folder --to-folder=$(TMP_SYNCS)serv_sync_pull_conf  @json:@extend:'{"name":"serv_sync_pull_conf","reset":true,"transport":{"target_rate":@preset:sync.bps@}}'
	$(BEG_FAI)$(CLI_TEST) server sync admin status @json:'{"name":"serv_sync_pull_conf"}'$(END_FAI_HIDE)
	$(CLI_TEST) server sync admin status $(TMP_SYNCS)serv_sync_pull_conf @json:'{"name":"serv_sync_pull_conf"}'
	$(INCMAN)$(CLI_TEST) server sync pull @preset:server.inside_folder --to-folder=$(TMP_SYNCS)serv_sync_pull_conf @json:@extend:'{"name":"serv_sync_pull_conf"}'
	$(INCMAN)$(CLI_TEST) server sync admin status $(TMP_SYNCS)serv_sync_pull_conf
	$(CLI_TEST) server sync admin overview $(TMP_SYNCS)serv_sync_pull_conf
	$(CLI_TEST) server sync admin file_info $(TMP_SYNCS)serv_sync_pull_conf
	@$(STOP_TEST) $@
$(F)serv_upload_ex: $(F)serv_mkdir
	@$(START_TEST) $@
	echo $(TST_ASC_LCL_PATH) > $(DIR_TMP)filelist.txt
	echo $(TST_ASC_LCL_PATH) > $(DIR_TMP)file_pair_list.txt
	touch -t 197001010000 ../tmp/ascli_home/filelists/to_be_collected
	$(CLI_TEST) config echo @extend:@preset:server.inside_folder@/other_name --format=text >> $(DIR_TMP)file_pair_list.txt
	$(INCMAN)$(CLI_TEST) server upload --sources=@ts --transfer-info=@json:'{"ascp_args":["--file-list","'"$(DIR_TMP)filelist.txt"'"]}' --to-folder=@preset:server.inside_folder 
	$(INCMAN)$(CLI_TEST) server upload --sources=@ts --transfer-info=@json:'{"ascp_args":["--file-pair-list","'"$(DIR_TMP)file_pair_list.txt"'"]}'
	@$(STOP_TEST) $@
$(F)serv_md5: $(F)serv_upload1
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server md5sum @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)serv_down_lcl: $(F)serv_upload1
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server download @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME) --to-folder=$(DIR_TMP). --transfer-info=@json:'{"wss":false,"resume":{"iter_max":1}}'
	@$(STOP_TEST) $@
$(F)serv_down_from_node: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server download @preset:server.large_file --to-folder=@preset:server.upload_folder --transfer=node --ts.resume_policy=none
	@$(STOP_TEST) $@
$(F)serv_down_from_node_fail: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(CLI_TEST) server download file_does_not_exist.random --to-folder=@preset:server.upload_folder --transfer=node$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)serv_cp: $(F)serv_upload1
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server cp @extend:@preset:server.inside_folder@/$(TST_ASC_FILENAME) @extend:@preset:server.upload_folder@/200KB.2
	@$(STOP_TEST) $@
$(F)serv_mv: $(F)serv_cp
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server mv @extend:@preset:server.upload_folder@/200KB.2 @extend:@preset:server.upload_folder@/to.delete
	@$(STOP_TEST) $@
$(F)serv_delete: $(F)serv_mv
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server delete @extend:@preset:server.upload_folder@/to.delete
	@$(STOP_TEST) $@
$(F)serv_cleanup1: $(F)serv_cp $(F)serv_down_from_node $(F)serv_down_lcl $(F)serv_md5
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server delete @preset:server.inside_folder
	@$(STOP_TEST) $@
$(F)serv_info: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server info
	@$(STOP_TEST) $@
$(F)serv_du: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server du /
	@$(STOP_TEST) $@
$(F)serv_df: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server df
	@$(STOP_TEST) $@
$(F)serv_health_xfer_nagios: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server health transfer --to-folder=@preset:server.upload_folder --format=nagios 
	$(BEG_ERR)$(CLI_TEST) server health transfer --to-folder=/wrong --format=nagios$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)serv_key: $(TMP_EXISTS)
	@$(START_TEST) $@
	set -x&&\
	aspera_key_path=$$($(CLI_TEST) config ascp info --fields=ssh_private_rsa) &&\
	$(INCMAN)$(CLI_TEST) server browse / --password=@none: --ssh-options=@json:'{"number_of_password_prompts":0}' --ssh-keys=$$aspera_key_path
	@$(STOP_TEST) $@
$(F)asession: $(TMP_EXISTS)
	@$(START_TEST) $@
	set -x&&\
	remote_host=$$($(CLI_TEST) config preset get server_user url)&&\
	remote_host=$${remote_host#*://}&&\
	remote_port=$${remote_host#*:}&&\
	remote_host=$${remote_host%:*}&&\
	remote_user=$$($(CLI_TEST) config preset get server_user username)&&\
	remote_pass=$$($(CLI_TEST) config preset get server_user password)&&\
	$(DIR_BIN)asession @json:@extend:'{"loglevel":"info","spec":{"remote_host":"'"$${remote_host}"'","remote_user":"'"$${remote_user}"'","ssh_port":'$${remote_port}',"remote_password":"'"$${remote_pass}"'","direction":"receive","destination_root":"$(DIR_TMP).","resume_policy":"none","paths":[{"source":"/aspera-test-dir-large/100MB"}]}}'
	@$(STOP_TEST) $@
$(F)serv_pr1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload 'faux:///test1?100m' 'faux:///test2?100m' --to-folder=/Upload --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none","precalculate_job_size":true}' --transfer-info=@json:'{"quiet":false}' --progress=no
	@$(STOP_TEST) $@
$(F)serv_pr2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) server upload 'faux:///test1?100m' 'faux:///test2?100m' --to-folder=/Upload --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none","precalculate_job_size":true}'
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tserver,$(F)serv_health $(F)serv_health_bad $(F)serv_detect $(F)serv_wizard $(F)serv_error $(F)serv_browse $(F)serv_mkdir $(F)serv_upload1 $(F)serv_upload2 $(F)serv_upload3 $(F)serv_upload5 $(F)serv_sync_pull_args $(F)serv_sync_pull_conf $(F)serv_upload_ex $(F)serv_md5 $(F)serv_down_lcl $(F)serv_down_from_node $(F)serv_down_from_node_fail $(F)serv_cp $(F)serv_mv $(F)serv_delete $(F)serv_cleanup1 $(F)serv_info $(F)serv_du $(F)serv_df $(F)asession $(F)serv_health_xfer_nagios $(F)serv_key))
#######################################################################################################################
$(F)f4_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex health
	@$(STOP_TEST) $@
$(F)f4_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) faspex health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(F)f4_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) config detect @preset:faspex4_user.url
	@$(STOP_TEST) $@
$(F)f4_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:faspex4_user.url faspex --username=test --password=test
	@$(STOP_TEST) $@
$(F)f4_pack_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package list --query.max=5
	@$(STOP_TEST) $@
$(F)f4_pack_send: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package send --delivery-info=@json:@extend:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:misc.email_internal@","@preset:faspex4_user.username@"]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
	@sleep 8
$(F)f4_prs: $(F)f4_pack_send
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package list --query.max=1 --fields=package_id --display=data --format=csv --output=$(STATE)f4_prs1
	$(CLI_TEST) faspex package receive $$(cat $(STATE)f4_prs1) --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) faspex package list --box=sent --query.max=1 --fields=package_id --display=data --format=csv --output=$(STATE)f4_prs2
	$(INCMAN)$(CLI_TEST) faspex package receive $$(cat $(STATE)f4_prs2) --to-folder=$(DIR_TMP). --box=sent
	@$(STOP_TEST) $@
$(F)f4_pri: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) faspex package list --query.max=1 --fields=package_id --display=data --format=csv --output=$(STATE)f4_pri1
	$(INCMAN)$(CLI_TEST) faspex package receive $$(cat $(STATE)f4_pri1) --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(F)f4_prl: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) faspex package receive --to-folder=$(DIR_TMP). --link=@preset:faspex4.link_recv_from_user$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)f4_prall: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package receive ALL --once-only=yes --to-folder=$(DIR_TMP). --query=@json:'{"max":10}'
	@$(STOP_TEST) $@
$(F)f4_pslu: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package send --link=@preset:faspex4.link_send_to_user --delivery-info=@json:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)f4_psld: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex package send --link=@preset:faspex4.link_send_to_dropbox --delivery-info=@json:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)f4_remote_src: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex source list
	$(INCMAN)$(CLI_TEST) faspex source info %name:@preset:faspex4.src --storage=@preset:faspex4_storage
	$(INCMAN)$(CLI_TEST) faspex source node %name:@preset:faspex4.src br / --storage=@preset:faspex4_storage
	$(INCMAN)$(CLI_TEST) faspex package send --delivery-info=@json:@extend:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:misc.email_internal@"]}' --remote-source=@extend:%name:@preset:faspex4.src sample_source.txt
	@$(STOP_TEST) $@
$(F)f4_misc: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex me
	$(INCMAN)$(CLI_TEST) faspex address_book
	$(INCMAN)$(CLI_TEST) faspex login_methods
	@$(STOP_TEST) $@
$(F)f4_v4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=faspex4_admin faspex v4 dropbox list
	$(INCMAN)$(CLI_TEST) --preset=faspex4_admin faspex v4 dmembership list
	$(INCMAN)$(CLI_TEST) --preset=faspex4_admin faspex v4 workgroup list
	$(INCMAN)$(CLI_TEST) --preset=faspex4_admin faspex v4 wmembership list
	$(INCMAN)$(CLI_TEST) --preset=faspex4_admin faspex v4 user list
	$(INCMAN)$(CLI_TEST) faspex v4 metadata_profile list
	@$(STOP_TEST) $@
$(F)f4_db1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex dropbox list --recipient=@extend:"*@preset:faspex4.dbx@"
	$(INCMAN)$(CLI_TEST) faspex package send --delivery-info=@json:@extend:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["*@preset:faspex4.dbx@"]}' $(TST_ASC_LCL_PATH)
	$(INCMAN)$(CLI_TEST) faspex package list --recipient=@extend:"*@preset:faspex4.dbx@" --format=csv --fields=package_id --query.max=1 --output=$(STATE)f4_db_id1
	$(INCMAN)$(CLI_TEST) faspex package receive $$(cat $(STATE)f4_db_id1) --recipient=@extend:"*@preset:faspex4.dbx@" --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) faspex dropbox list --recipient=@extend:"*@preset:faspex4.dbx@"
	$(INCMAN)$(CLI_TEST) faspex package send --delivery-info=@json:@extend:'{"title":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["*@preset:faspex4.wkg@"]}' $(TST_ASC_LCL_PATH)
	sleep 10
	$(INCMAN)$(CLI_TEST) faspex package list --recipient=@extend:"*@preset:faspex4.wkg@" --format=csv --fields=package_id --query.max=1 --output=$(STATE)f4_db_id2
	$(INCMAN)$(CLI_TEST) faspex package receive $$(cat $(STATE)f4_db_id2) --recipient=@extend:"*@preset:faspex4.wkg@" --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
NOT_TESTED=$(F)f4_health $(F)f4_health_bad $(F)f4_detect $(F)f4_wizard $(F)f4_pack_list $(F)f4_pack_send $(F)f4_prs $(F)f4_pri $(F)f4_pslu $(F)f4_psld $(F)f4_remote_src $(F)f4_prall $(F)f4_misc $(F)f4_v4 $(F)f4_db1 $(F)f4_prl
$(eval $(call test_suite_all,tfaspex4,$(NOT_TESTED)))
#######################################################################################################################
$(F)cons_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) console health
	@$(STOP_TEST) $@
$(F)cons_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) console health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(F)cons_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) config detect @preset:console_admin.url
	@$(STOP_TEST) $@
$(F)cons_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:console_admin.url console --preset=console_admin
	@$(STOP_TEST) $@
$(F)cons_cur_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) console transfer current list --query=@json:'{"filter1":"transfer_name","comp1":"contain","val1":"aoc"}'
	@$(STOP_TEST) $@
$(F)cons_cur_lst_ex: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) console transfer current list --query.filter='(transfer_name contain aoc)'
	@$(STOP_TEST) $@
$(F)cons_cur_lst_one: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) console transfer current list --fields=id --format=csv | tail -n 1 > $(STATE)console_xfer_id
	@$(STOP_TEST) $@
$(F)cons_cur_show_one: $(F)cons_cur_lst_one
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) console transfer current show $$(cat $(STATE)console_xfer_id)
	$(INCMAN)$(CLI_TEST) console transfer current files $$(cat $(STATE)console_xfer_id)
	$(BEG_IGN)$(CLI_TEST) console transfer current resume $$(cat $(STATE)console_xfer_id)$(END_IGN)
	@$(STOP_TEST) $@
$(F)cons_sma_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) console transfer smart list
	@$(STOP_TEST) $@
$(F)cons_sma_sta: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) console transfer smart sub @preset:console.smart_id @json:@extend:'{"source":{"paths":["@preset:console.smart_file@"]},"source_type":"user_selected"}'$(END_FAI_SHOW)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tconsole,$(F)cons_health $(F)cons_health_bad $(F)cons_detect $(F)cons_wizard $(F)cons_cur_lst $(F)cons_cur_lst_ex $(F)cons_cur_show_one $(F)cons_sma_lst $(F)cons_sma_sta))
#######################################################################################################################
$(F)nd_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node health
	@$(STOP_TEST) $@
$(F)nd_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) node health --url=https://wrong.example.com
	@$(STOP_TEST) $@
$(F)nd_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:node_user.url
	@$(STOP_TEST) $@
$(F)nd_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:node_user.url node --username=test --password=test
	@$(STOP_TEST) $@
$(F)nd_info: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node info --fpac='function FindProxyForURL(url,host){return "DIRECT"}'
	@$(STOP_TEST) $@
$(F)nd_lic: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node license
	@$(STOP_TEST) $@
$(F)nd_det: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node api_details
	@$(STOP_TEST) $@
$(F)nd_tra: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node transport
	@$(STOP_TEST) $@
$(F)nd_bro: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node browse / --log-level=trace2
	@$(STOP_TEST) $@
$(F)nd_sea: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node search / --query=@json:'{"sort":"mtime"}'
	@$(STOP_TEST) $@
$(F)nd_spa: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node space /
	@$(STOP_TEST) $@
$(F)nd_del_err: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node delete /a_folder$(END_IGN)
	@$(STOP_TEST) $@
$(F)nd_folder: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node mkdir @extend:@preset:server.upload_folder@/a_folder
	$(INCMAN)$(CLI_TEST) node mklink @extend:@preset:server.upload_folder@/a_folder @extend:@preset:server.upload_folder@/tdlink
	$(INCMAN)$(CLI_TEST) node mkfile @extend:@preset:server.upload_folder@/a_file1 "hello world"
	$(INCMAN)$(CLI_TEST) node rename @preset:server.upload_folder a_file1 a_file
	$(INCMAN)$(CLI_TEST) node delete @list:@extend:,@preset:server.upload_folder@/a_folder,@preset:server.upload_folder@/tdlink,@preset:server.upload_folder@/a_file
	@$(STOP_TEST) $@
$(F)nd2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node upload $(TST_ASC_LCL_PATH) --to-folder=@preset:server.upload_folder --ts=@json:'{"target_rate_cap_kbps":10000}'
	$(INCMAN)$(CLI_TEST) node download @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) node delete @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)nd_slash: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node slash
	@$(STOP_TEST) $@
$(F)nd2_http: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node upload $(TST_ASC_LCL_PATH) --to-folder=@preset:server.upload_folder --ts=@json:'{"target_rate_cap_kbps":10000}'
	$(INCMAN)$(CLI_TEST) node cat @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME)
	$(INCMAN)$(CLI_TEST) node delete @extend:@preset:server.upload_folder@/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)nd_2_nd_xfer: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node upload --to-folder=@preset:server.upload_folder --sources=@ts --ts=@json:'{"paths":[{"source":"/aspera-test-dir-small/10MB.2"}],"precalculate_job_size":true}' --transfer=node --transfer-info=@json:@extend:'{"url":"@preset:node_user.url@","username":"@preset:node_user.username@","password":"@preset:node_user.password@"}'
	$(BEG_IGN)$(CLI_TEST) node delete @extend:@preset:server.upload_folder@/10MB.2$(END_IGN)
	@$(STOP_TEST) $@
$(F)nd_service: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node --preset=node_ak_adm service delete service1$(END_IGN)
	@echo "waiting a little...";$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service create @json:'{"id":"service1","type":"WATCHD","run_as":{"user":"user1"}}'
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service list
	@echo "waiting a little...";$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service delete service1
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service list
	@echo "waiting a little...";$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service list
	@echo "waiting a little...";$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm service list
	@$(STOP_TEST) $@
$(F)nd_xfer_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node transfer list --query=@json:'{"active_only":true}'
	$(INCMAN)$(CLI_TEST) node transfer list --query=@json:'{"reset":true}' --once-only=yes
	$(INCMAN)$(CLI_TEST) node transfer list --once-only=yes
	$(CLI_TEST) node transfer list --once-only=yes
	$(INCMAN)$(CLI_TEST) node transfer sessions
	@$(STOP_TEST) $@
$(F)nd_xfer_ops: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) node upload --to-folder=@preset:server.upload_folder --ts=@json:'{"target_rate_kbps":1000,"resume_policy":"none"}' 'faux:///bigfile?10G' --progress=no & sleep 2
	$(INCMAN)$(CLI_TEST) node transfer list --query=@json:'{"active_only":true,"count":1}' --fields=id --output=$(STATE)nd_xfer_id
	$(INCMAN)$(CLI_TEST) node transfer show $$(cat $(STATE)nd_xfer_id)
	$(INCMAN)$(CLI_TEST) node transfer modify $$(cat $(STATE)nd_xfer_id) @json:'{"target_rate_kbps":10000}'
	$(INCMAN)$(CLI_TEST) node transfer show $$(cat $(STATE)nd_xfer_id)
	$(INCMAN)$(CLI_TEST) node transfer cancel $$(cat $(STATE)nd_xfer_id)
	$(INCMAN)$(CLI_TEST) node transfer bandwidth_average
	$(INCMAN)$(CLI_TEST) node transfer sessions
	@$(STOP_TEST) $@
$(F)node_basic_token: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node basic_token
	@$(STOP_TEST) $@
$(F)nd_browser: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node asperabrowser
	@$(STOP_TEST) $@
$(F)nd8: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node upload --username=@preset:aoc.ak_name --password=@preset:aoc.ak_secret $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)nd_central_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node central session list
	$(INCMAN)$(CLI_TEST) node central file list
	$(INCMAN)$(CLI_TEST) node central file modify --validator=1 @json:'{"files":[]}'
	@$(STOP_TEST) $@
$(F)nd_watch_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node watch_folder list --preset=node_ak_adm
	$(BEG_ERR)$(CLI_TEST) node watch_folder create @json:'{"source":{"path":"/src1"},"target":{"path":"/dst1"}}' --preset=node_ak_adm$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)nd_stream_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node stream list --preset=node_ak_adm
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tnodegen3,$(F)nd_health $(F)nd_health_bad $(F)nd_detect $(F)nd_wizard $(F)nd_info $(F)nd_lic $(F)nd_det $(F)nd_tra $(F)nd_bro $(F)nd_sea $(F)nd_spa $(F)nd_del_err $(F)nd_folder $(F)nd_slash $(F)nd2_http $(F)nd2 $(F)nd_2_nd_xfer $(F)nd_service $(F)nd_xfer_lst $(F)nd_xfer_ops $(F)node_basic_token $(F)nd_browser $(F)nd8 $(F)nd_central_1 $(F)nd_watch_1 $(F)nd_stream_1))
#######################################################################################################################
tnode: tnodegen3 tndak
clean_tnode: clean_tnodegen3 clean_tndak
#######################################################################################################################
$(F)nd_ak: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key list
	@$(STOP_TEST) $@
$(F)nd_ak1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name node_info /
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name browse /
	$(BEG_ERR)$(CLI_TEST)node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @json:'{}'$(END_ERR_HIDE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder @ruby:'->(f){f["name"].end_with?(".jpg")}'
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder @re:'\.jpg$$'
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name find @preset:aoc.test_folder
	@$(STOP_TEST) $@
$(F)nd_ak_mkdir: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete /tst_nd_ak$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name mkdir /tst_nd_ak
	$(TEMPORIZE_CREATE)
	@$(STOP_TEST) $@
$(F)nd_ak_mkfile: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete /mkfile.txt$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name mkfile /mkfile.txt "hello world"
	$(TEMPORIZE_CREATE)
	@$(STOP_TEST) $@
$(F)nd_ak_mklink: $(F)nd_ak_mkfile
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete /mklink.txt$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name mklink /mklink.txt --query=@json:'{"target":"/mkfile.txt","target_node_id":"123"}'
	$(TEMPORIZE_CREATE)
	@$(STOP_TEST) $@
$(F)nd_ak_mvdir: $(F)nd_ak_mkdir
	@$(START_TEST) $@
	$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name browse / --node-cache=no
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name rename /tst_nd_ak test_nd_ak2
	@$(STOP_TEST) $@
$(F)nd_ak_deldir: $(F)nd_ak_mvdir
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete /test_nd_ak2
	@$(STOP_TEST) $@
$(F)nd_ak3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name upload 'faux:///test_nd_ak3?100k' --default-ports=no
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name download test_nd_ak3 --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name show /test_nd_ak3
	$(BEG_ERR)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name thumbnail /test_nd_ak3$(END_ERR_HIDE)
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name delete test_nd_ak3
	@$(STOP_TEST) $@
$(F)nd_ak4: $(F)nd_ak3
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node --preset=node_ak_adm access_key do @preset:aoc.ak_name show %id:1
	@$(STOP_TEST) $@
$(F)nd_ak_bearer: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) node -N --preset=tst_node_preview access_key delete @preset:ak_creds.username$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview access_key create @json:@extend:'{"id":"@preset:ak_creds.username@","secret":"@preset:ak_creds.password@","storage":{"type":"local","path":"/"}}'
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key show %id:self
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key set_bearer_key self @file:@preset:file.private_key
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key do self show / --fields=id --output=$(STATE)root_id
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key do self permission %id:$$(cat $(STATE)root_id) create @json:'{"access_type":"user","access_id":"666"}'
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key do self permission / show 1
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds bearer_token @file:@preset:file.private_key @json:'{"user_id":"666"}' --output=$(STATE)bearer_666
	$(INCMAN)$(CLI_TEST) node -N --url=@preset:tst_node_preview.url --password="Bearer $$(cat $(STATE)bearer_666)" --root-id=$$(cat $(STATE)root_id) access_key do self br /
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview --preset=ak_creds access_key do self permission / delete 1
	$(INCMAN)$(CLI_TEST) node -N --preset=tst_node_preview access_key delete @preset:ak_creds.username
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tndak,$(F)nd_ak $(F)nd_ak1 $(F)nd_ak_mkdir $(F)nd_ak_mkfile $(F)nd_ak_mklink $(F)nd_ak_mvdir $(F)nd_ak_deldir $(F)nd_ak3 $(F)nd_ak4 $(F)nd_ak_bearer))
#######################################################################################################################
$(F)aoc_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:aoc.org aoc
	@$(STOP_TEST) $@
$(F)aoc_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config tokens flush
	$(INCMAN)$(CLI_TEST) config tokens list
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:aoc.org aoc --key-path=@preset:file.private_key --username=@preset:aoc.user_email --use-generic-client=yes
	@$(STOP_TEST) $@
$(F)aoc_wizard_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config tokens flush
	$(BEG_ERR)$(INCMAN)$(CLI_TEST) config tokens show foobar$(END_ERR_HIDE)
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:aoc.org aoc mypreset --key-path=@preset:file.private_key --username=@preset:aoc.user_email
	@$(STOP_TEST) $@
$(F)aoc_faspex_gateway: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -f $(DIR_TMP)pid_aoc_faspex_gateway
	$(INCMAN)$(CLI_TEST) aoc gateway --pid-file=$(DIR_TMP)pid_aoc_faspex_gateway @json:'{"url":"https://localhost:12345/aspera/faspex"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_aoc_faspex_gateway;do sleep 1;let --i;done
	kill -0 $$(cat $(DIR_TMP)pid_aoc_faspex_gateway)
	$(CLI_TEST) -N faspex --url=https://localhost:12345/aspera/faspex --username=_unused_ --password=_unused_ --warn-insecure=yes package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway aoc"}' 'faux:///test1?1m'
	kill -TERM $$(cat $(DIR_TMP)pid_aoc_faspex_gateway)
	let i=10;while test $$i -gt 0 -a -f $(DIR_TMP)pid_aoc_faspex_gateway;do sleep 1;let --i;done
	@$(STOP_TEST) $@
$(F)aocg1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc -N servers
	$(INCMAN)$(CLI_TEST) aoc -N remind --username=@preset:aoc.user_email
	@$(STOP_TEST) $@
$(F)aocg2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc bearer_token --display=data --scope=user:all
	@$(STOP_TEST) $@
$(F)aocg3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc organization
	$(INCMAN)$(CLI_TEST) aoc organization --format=image --fields=background_image_url --ui=text
	$(INCMAN)$(CLI_TEST) aoc tier_restrictions
	@$(STOP_TEST) $@
$(F)aocg4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user workspaces list
	@$(STOP_TEST) $@
$(F)aoc_user_profile: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user profile show
	@$(STOP_TEST) $@
$(F)aocg6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user profile modify @json:'{"name":"dummy change"}'
	@$(STOP_TEST) $@
$(F)aocuprefshow: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user pref show
	@$(STOP_TEST) $@
$(F)aocuprefmod: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user pref modify @json:'{"default_language":"en-us"}'
	@$(STOP_TEST) $@
$(F)aocucontactlist: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user contacts list
	@$(STOP_TEST) $@
$(F)aocg7: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages shared_inboxes list
	$(INCMAN)$(CLI_TEST) aoc packages shared_inboxes show %name:@preset:aoc.shared_inbox_name
	@$(STOP_TEST) $@
$(F)aocg8: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc user workspaces current
	@$(STOP_TEST) $@
$(F)aoc_webauth: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) aoc --preset=aoc_web user profile show
	$(CLI_TEST) aoc --preset=aoc_web user profile show --http-options=@json:'{"token_refresh_threshold":10000000000}'
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocgen,$(F)aoc_detect $(F)aoc_wizard $(F)aoc_wizard_2 $(F)aocg1 $(F)aocg2 $(F)aocg3 $(F)aocg4 $(F)aoc_user_profile $(F)aocg6 $(F)aocuprefshow $(F)aocuprefmod $(F)aocucontactlist $(F)aocg7 $(F)aocg8))
#######################################################################################################################
$(F)aocfbr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files browse /
	@$(STOP_TEST) $@
$(F)aocfbr1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files browse @preset:aoc.remote_folder
	$(INCMAN)$(CLI_TEST) aoc files browse @extend:@preset:aoc.remote_folder@/
	$(INCMAN)$(CLI_TEST) aoc files browse @preset:aoc.remote_file
	@$(STOP_TEST) $@
$(F)aocfbt: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files bearer_token_node / --cache-tokens=no
	@$(STOP_TEST) $@
$(F)aocffin: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files find /
	$(INCMAN)$(CLI_TEST) aoc files find / '\.partial$$'
	$(INCMAN)$(CLI_TEST) aoc files find / @ruby:'->(f){f["type"].eql?("file")}'
	@$(STOP_TEST) $@
$(F)aoc_tstsrc: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) aoc files delete /testsrc$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) aoc files mkdir /testsrc
	@$(STOP_TEST) $@
$(F)aoc_some_folder: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) aoc files delete /some_folder$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(CLI_TEST) aoc files mkdir /some_folder
	$(TEMPORIZE_CREATE)
	@$(STOP_TEST) $@
$(F)aoc_tstdst: $(F)aoc_some_folder
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) aoc files delete /testdst$(END_IGN)
	$(TEMPORIZE_FILE)
	$(CLI_TEST) aoc files browse / --node-cache=no
	$(INCMAN)$(CLI_TEST) aoc files modify /some_folder @json:'{"mount_point":false}'
	$(INCMAN)$(CLI_TEST) aoc files rename /some_folder testdst
	@$(STOP_TEST) $@
$(F)aocfupl: $(F)aoc_tstsrc
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files upload --to-folder=/testsrc $(TST_ASC_LCL_PATH)
	$(INCMAN)$(CLI_TEST) aoc files upload --to-folder=/testsrc $(TST_ASC_LCL_PATH) $(TST_UTF_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aocftr: $(F)aocfupl $(F)aoc_tstdst
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files transfer push /testsrc --to-folder=/testdst $(TST_ASC_FILENAME)
	$(CLI_TEST) aoc files upload --to-folder=/testdst $(TST_UTF_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aocndinf: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files node_info /testdst --format=json --display=data | $(INCMAN)$(CLI_TEST) aoc files upload --workspace=@preset:aoc.other_workspace --to-folder=@preset:aoc.other_folder $(TST_ASC_FILENAME) --transfer=node --transfer-info=@json:@stdin:
	@$(STOP_TEST) $@
$(F)aocfdel: $(F)aocftr $(F)aocndinf
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files delete /testsrc
	@$(STOP_TEST) $@
$(F)aocfbearnode: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files bearer /
	@$(STOP_TEST) $@
$(F)aocfdownd: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files down --to-folder=$(DIR_TMP). testdst/$(TST_ASC_FILENAME) testdst/$(TST_UTF_FILENAME)
	$(CLI_TEST) aoc files down --to-folder=$(DIR_TMP). testdst/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)aocfdownc: $(F)aoc_tstdst
	@$(START_TEST) $@
	@rm -f $(DIR_CONNECT_DOWNLOAD)$(TST_ASC_FILENAME)
	@-killall asperaconnect
	@sleep 1
	$(INCMAN)$(CLI_TEST) aoc files download --transfer=connect testdst/$(TST_ASC_FILENAME)
	@rm -f $(DIR_CONNECT_DOWNLOAD)$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)aocfdowna: $(F)aoc_tstdst
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files download --transfer=desktop testdst/$(TST_ASC_FILENAME)
	@rm -f $(DIR_CONNECT_DOWNLOAD)$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)aocfhttpd: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files cat testdst/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)aocfv3inf: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files v3 info
	@$(STOP_TEST) $@
$(F)aoc_sync_pull_conf_parms: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)aoc_sync_pull_conf_parms
	mkdir -p $(TMP_SYNCS)aoc_sync_pull_conf_parms
	$(INCMAN)$(CLI_TEST) aoc files sync pull /testdst --to-folder=$(TMP_SYNCS)aoc_sync_pull_conf_parms  @json:@extend:'{"reset":true,"transport":{"target_rate":@preset:sync.bps@}}'
	$(INCMAN)$(CLI_TEST) aoc files sync admin status $(TMP_SYNCS)aoc_sync_pull_conf_parms
	@$(STOP_TEST) $@
$(F)aoc_sync_conf_pull_params: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)aoc_sync_conf_pull_params
	mkdir -p $(TMP_SYNCS)aoc_sync_conf_pull_params
	$(INCMAN)$(CLI_TEST) aoc files sync pull /testdst --to-folder=$(TMP_SYNCS)aoc_sync_conf_pull_params  @json:@extend:'{"reset":true,"transport":{"target_rate":@preset:sync.bps@}}'
	$(INCMAN)$(CLI_TEST) aoc files sync admin status $(TMP_SYNCS)aoc_sync_conf_pull_params
	@$(STOP_TEST) $@
$(F)aoc_file_id_1: $(F)aocftr
	@$(START_TEST) $@
	$(CLI_TEST) aoc files br testdst/$(TST_ASC_FILENAME) --fields=id --format=csv --display=data --output=$(STATE)aoc_file_id
	@$(STOP_TEST) $@
$(F)aoc_file_id_2: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files show %id:$$(cat $(STATE)aoc_file_id)
	@$(STOP_TEST) $@
$(F)aoc_file_id_3: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files show /
	@$(STOP_TEST) $@
$(F)aoc_file_id_4: $(F)aocftr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files show testdst/$(TST_ASC_FILENAME)
	@$(STOP_TEST) $@
$(F)aoc_file_id_5: $(F)aocftr
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) aoc files mkdir @preset:aoc.test_folder$(END_IGN)
	@$(STOP_TEST) $@
$(F)aoc_file_id_6: $(F)aoc_file_id_5
	@$(START_TEST) $@
	$(CLI_TEST) aoc files upload --to-folder=@preset:aoc.test_folder --src-type=pair @preset:file.mpg video_file.mpg
	@echo 'waiting for preview'
	sleep 60
	@$(STOP_TEST) $@
$(F)aoc_file_id_7: $(F)aoc_file_id_5
	@$(START_TEST) $@
	$(CLI_TEST) aoc files upload --to-folder=@preset:aoc.test_folder --src-type=pair @preset:file.jpg image_file.jpg
	@$(STOP_TEST) $@
$(F)aoc_file_id_8: $(F)aoc_file_id_5
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files permission @preset:aoc.test_folder list
	@$(STOP_TEST) $@
$(F)aoc_file_id_9: $(F)aoc_file_id_6
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg
	@$(STOP_TEST) $@
$(F)aoc_file_id_10: $(F)aoc_file_id_6
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg --query=@json:'{"text":true,"double":true}'
	@$(STOP_TEST) $@
$(F)aoc_file_id_11: $(F)aoc_file_id_6
	@$(START_TEST) $@
	$(CLI_TEST) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg --query=@json:'{"text":true,"double":false}'
	@$(STOP_TEST) $@
$(F)aoc_file_id_12: $(F)aoc_file_id_6
	@$(START_TEST) $@
	env -u TERM_PROGRAM -u LC_TERMINAL $(CLI_TEST) aoc files thumbnail @extend:@preset:aoc.test_folder@/video_file.mpg
	@$(STOP_TEST) $@
#	$(INCMAN)$(CLI_TEST) aoc files modify @preset:aoc.test_folder
$(F)aocfpub: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files browse / -N --url=@preset:aoc.public_link_folder_no_pass
	$(INCMAN)$(CLI_TEST) aoc files browse / -N --url=@preset:aoc.public_link_folder_pass --password=@preset:aoc.public_link_password
	$(INCMAN)$(CLI_TEST) aoc files upload --to-folder=/ $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.public_link_folder_no_pass
	@$(STOP_TEST) $@
$(F)aoc_lnk_priv: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files browse / --url=@preset:aoc.private_link
	@$(STOP_TEST) $@
$(F)aocshlk2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files short_link /testdst private create
	@$(STOP_TEST) $@
$(F)aocshlk3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files short_link /testdst public create
	@$(STOP_TEST) $@
$(F)aocshlk1: $(F)aocshlk2 $(F)aocshlk3
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc files short_link /testdst private list
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocf,$(F)aocfbr $(F)aocfbr1 $(F)aocfbt $(F)aocffin $(F)aoc_tstsrc $(F)aoc_tstdst $(F)aocfupl $(F)aocftr $(F)aocndinf $(F)aocfdel $(F)aocfbearnode $(F)aocfdownd $(F)aocfdownc $(F)aocfdowna $(F)aocfhttpd $(F)aocfv3inf $(F)aoc_sync_pull_conf_parms $(F)aoc_sync_conf_pull_params $(F)aoc_file_id_1 $(F)aoc_file_id_2 $(F)aoc_file_id_3 $(F)aoc_file_id_4 $(F)aoc_file_id_5 $(F)aoc_file_id_6 $(F)aoc_file_id_7 $(F)aoc_file_id_8 $(F)aoc_file_id_9 $(F)aocfpub $(F)aoc_lnk_priv $(F)aocshlk1 $(F)aocshlk2 $(F)aocshlk3 $(F)aoc_faspex_gateway))
#######################################################################################################################
$(F)aoc_pack_send1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:misc.email_internal@"],"note":"my note"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aoc_pack_send2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:misc.email_external@"]}' --new-user-option=@json:'{"package_contact":true}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aocp2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages list
	@$(STOP_TEST) $@
$(F)aocp3: $(F)aoc_pack_send1
	@$(START_TEST) $@
	:>$(STATE)package_id3;while test -z "$$(cat $(STATE)package_id3)";do \
	$(CLI_TEST) aoc packages list --format=csv --fields=id --display=data --query=@json:'{"max":1,"archived":false,"has_content":true,"received":true,"completed":true}' --output=$(STATE)package_id3;\
	sleep 3;\
	date;\
	done
	$(INCMAN)$(CLI_TEST) aoc packages receive $$(cat $(STATE)package_id3) --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) aoc packages receive $$(cat $(STATE)package_id3) --to-folder=$(DIR_TMP). / --package-folder=name
	$(INCMAN)$(CLI_TEST) aoc packages browse $$(cat $(STATE)package_id3) /
	@$(STOP_TEST) $@
$(F)aocp4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages receive ALL --once-only=yes --to-folder=$(DIR_TMP). --lock-port=12345
	@$(STOP_TEST) $@
$(F)aocp5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc organization -N --url=@preset:aoc.public_link_recv_from_aoc_user
	@$(STOP_TEST) $@
$(F)aocp_send_pub_sh: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send @json:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)"}' $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.public_link_send_shared_inbox
	@$(STOP_TEST) $@
$(F)aocp_send_pub_usr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send @json:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)"}' $(TST_ASC_LCL_PATH) -N --url=@preset:aoc.public_link_send_aoc_user --password=@preset:aoc.public_link_send_use_pass
	@$(STOP_TEST) $@
$(F)aocp_recv_init: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages receive INIT --once-only=yes --query=@json:@extend:'{"dropbox_name":"@preset:aoc.shared_inbox_name@"}'
	@$(STOP_TEST) $@
$(F)aocp_send_shbx: $(F)aocp_recv_init
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send --workspace=@preset:aoc.workspace_shared_inbox @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:aoc.shared_inbox_name@"]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aocp_send_sh_meta_long: $(F)aocp_recv_init
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send --workspace=@preset:aoc.workspace_shared_inbox --validate-metadata=yes @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:aoc.shared_inbox_meta@"],"metadata":[{"input_type":"single-text","name":"Project Id","values":["123"]},{"input_type":"single-dropdown","name":"Type","values":["Opt2"]},{"input_type":"multiple-checkbox","name":"CheckThose","values":["Check1","Check2"]},{"input_type":"date","name":"Optional Date","values":["2021-01-13T15:02:00.000Z"]}]}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)aocp_send_sh_meta_short: $(F)aocp_recv_init
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages send --workspace=@preset:aoc.workspace_shared_inbox --validate-metadata=yes @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:aoc.shared_inbox_meta@"],"metadata":{"Project Id":"456","Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' $(TST_ASC_LCL_PATH)
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) aoc packages send --workspace=@preset:aoc.workspace_shared_inbox --validate-metadata=yes @json:@extend:'{"name":"$(notdir $@) $(PACKAGE_TITLE_BASE)","recipients":["@preset:aoc.shared_inbox_meta@"],"metadata":{"Type":"Opt2","CheckThose":["Check1","Check2"],"Optional Date":"2021-01-13T15:02:00.000Z"}}' $(TST_ASC_LCL_PATH)$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)aocp_recv_shbx: $(F)aocp_send_shbx $(F)aocp_send_sh_meta_long $(F)aocp_send_sh_meta_short
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages receive ALL --once-only=yes --to-folder=$(DIR_TMP). --lock-port=12345 --query=@json:@extend:'{"dropbox_name":"@preset:aoc.shared_inbox_name@","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false,"include_draft":false}' --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000}'
	@$(STOP_TEST) $@
$(F)aocp_list_shbx: $(F)aocp_send_shbx $(F)aocp_send_sh_meta_long $(F)aocp_send_sh_meta_short
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc packages list --query=@json:@extend:'{"dropbox_name":"@preset:aoc.shared_inbox_name@","sort":"-received_at","archived":false,"received":true,"has_content":true,"exclude_dropbox_packages":false}'
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocp,$(F)aoc_pack_send1 $(F)aoc_pack_send2 $(F)aocp2 $(F)aocp3 $(F)aocp4 $(F)aocp5 $(F)aocp5 $(F)aocp_send_pub_sh $(F)aocp_send_pub_usr $(F)aocp_send_shbx $(F)aocp_send_sh_meta_long $(F)aocp_send_sh_meta_short $(F)aocp_recv_shbx $(F)aocp_list_shbx))
#######################################################################################################################
$(F)aoc_adm_authp_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin auth_providers list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin subscription account
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin subscription usage
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin subscription usage MONTH
	@$(STOP_TEST) $@
$(F)aoc_adm_ws_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace dropbox %name:@preset:aoc.other_workspace list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace shared_folder %name:@preset:aoc.other_workspace list
	$(CLI_TEST) --preset=aoc_admin aoc admin workspace shared_folder %name:@preset:aoc.other_workspace list --query.max=1 --fields=id --output=$(STATE)shared_folder_id
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace shared_folder %name:@preset:aoc.other_workspace member $$(cat $(STATE)shared_folder_id) list
	@$(STOP_TEST) $@
$(F)aoc_adm_nd_events: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret v3 events
	@$(STOP_TEST) $@
$(F)aoc_adm_ak_create: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret mkdir /folder_sub
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret browse /folder_sub --node-cache=no
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret v3 access_key create @json:'{"id":"testsub1","storage":{"path":"/folder_sub"}}'
	@$(STOP_TEST) $@
$(F)aoc_adm_ak_del: $(F)aoc_adm_ak_create
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret v3 access_key delete testsub1
	@$(STOP_TEST) $@
$(F)aoc_adm_ak_dir_del: $(F)aoc_adm_ak_del
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret delete /folder_sub
	@$(STOP_TEST) $@
$(F)aoc_adm_nd_br: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret browse /
	@$(STOP_TEST) $@
$(F)aoc_adm_nd_mkdir: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret delete /folder1 --node-cache=no$(END_IGN)
	sleep 4
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret mkdir /folder1
	$(TEMPORIZE_CREATE)
	$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret browse / --node-cache=no
	@$(STOP_TEST) $@
$(F)aoc_adm_nd_rmdir: $(F)aoc_adm_nd_mkdir
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name --secret=@preset:aoc.ak_secret delete /folder1
	@$(STOP_TEST) $@
$(F)aoc_adm_wsm_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace_membership list --fields=ALL --query=@json:'{"page":1,"per_page":50,"embed":"member","inherited":false,"workspace_id":11363,"sort":"name"}'
	@$(STOP_TEST) $@
$(F)aoc15: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin analytics transfers organization --query=@json:'{"status":"completed","direction":"receive","limit":2}' --notify-to=@preset:misc.email_external --notify-template=@ruby:'%Q{From: <%=from_name%> <<%=from_email%>>\nTo: <<%=to%>>\nSubject: <%=ev["files_completed"]%> files received\n\n<%=ev.to_yaml%>}'
	@$(STOP_TEST) $@
$(F)aoc_ana_tr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) --preset=aoc_admin aoc admin analytics transfers organization --query=@json:'{"status":"completed","direction":"receive","limit":1}' --fields=uuid --output=$(STATE)aoc_transfer_id
	@$(STOP_TEST) $@
$(F)aoc_ana_files: $(F)aoc_ana_tr
	@$(START_TEST) $@
	$(CLI_TEST) --preset=aoc_admin aoc admin analytics files organization '' @ruby:'File.read("$(STATE)aoc_transfer_id").chomp'
	@$(STOP_TEST) $@
$(F)aoc16: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin analytics transfers users --once-only=yes
#	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin analytics transfers nodes
	@$(STOP_TEST) $@
$(F)aoc_adm_res_01: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin self show
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin organization show
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin user list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin user modify @extend:%name:@preset:aoc.user_email@ @json:'{"deactivated":false}'
	@$(STOP_TEST) $@
$(F)aoc_adm_res_02: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin group list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin client list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin contact list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin dropbox list
	@$(STOP_TEST) $@
$(F)aoc_adm_res_03: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin operation list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin package list --http-options=@json:'{"read_timeout":120.0}'
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin saml_configuration list
	@$(STOP_TEST) $@
$(F)aoc_adm_res_04: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin dropbox_membership list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin workspace_membership list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin short_link list
	@$(STOP_TEST) $@
$(F)aoc_adm_res_05: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin application list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin client_access_key list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin kms_profile list
	@$(STOP_TEST) $@
$(F)aoccltreg: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin client_registration_token create @json:'{"data":{"name":"test_client_reg1","client_subject_scopes":["alee","aejd"],"client_subject_enabled":true}}'
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin client_registration_token list
	$(CLI_TEST) --preset=aoc_admin aoc admin client_registration_token list --select=@json:'{"data.name":"test_client_reg1"}' --fields=id --display=data --query.max=1 --output=$(STATE)client_reg_id
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin client_registration_token delete $$(cat $(STATE)client_reg_id)
	@$(STOP_TEST) $@
$(F)aocadmndcr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name delete test_shared_folder --node-cache=no$(END_IGN)
	$(BEG_IGN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name browse test_shared_folder --node-cache=no$(END_IGN)
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name mkdir test_shared_folder
	$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name browse test_shared_folder --node-cache=no
	@$(STOP_TEST) $@
$(F)aocadmndsh1: $(F)aocadmndcr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name perm test_shared_folder create @json:'{"with":"","as":"other_name_shared"}' --workspace=@preset:aoc.workspace_shared_inbox
	@$(STOP_TEST) $@
$(F)aocadmndsh2: $(F)aocadmndsh1
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name perm test_shared_folder create @json:@extend:'{"with":"@preset:aoc.user_email@","as":"other_name_shared"}' --workspace=@preset:aoc.workspace_shared_inbox
	@$(STOP_TEST) $@
$(F)aocadmndsh3: $(F)aocadmndsh1
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name perm test_shared_folder create @json:@extend:'{"with":"@preset:aoc.user_group@","as":"other_name_shared"}' --workspace=@preset:aoc.workspace_shared_inbox
	@$(STOP_TEST) $@
$(F)aocadmndsh4: $(F)aocadmndsh2 $(F)aocadmndsh3
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin node do %name:@preset:aoc.node_name delete test_shared_folder
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocadm,$(F)aoc_adm_authp_lst $(F)aoc_adm_ws_lst $(F)aoc_adm_nd_events $(F)aoc_adm_nd_br $(F)aoc_adm_nd_mkdir $(F)aoc_adm_ak_create $(F)aoc_adm_ak_del $(F)aoc_adm_ak_dir_del $(F)aoc_adm_nd_rmdir $(F)aoc_adm_wsm_lst $(F)aoc15 $(F)aoc_ana_files $(F)aoc16 $(F)aoc_adm_res_01 $(F)aoc_adm_res_02 $(F)aoc_adm_res_03 $(F)aoc_adm_res_04 $(F)aoc_adm_res_05 $(F)aoccltreg $(F)aocadmndsh4))
#######################################################################################################################
$(F)aocat4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc admin ats cluster list
	@$(STOP_TEST) $@
$(F)aocat5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc admin ats cluster clouds
	@$(STOP_TEST) $@
$(F)aocat6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc admin ats cluster show --cloud=aws --region=eu-west-1
	@$(STOP_TEST) $@
$(F)aocat7: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) aoc admin ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@$(STOP_TEST) $@
# see https://developer.ibm.com/api/view/aspera-prod:ibm-aspera:title-IBM_Aspera#113433
$(F)aocat8: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key delete ak1ibmcloud$(END_IGN)
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key create --cloud=softlayer --region=@preset:icos.region @json:@extend:'{"id":"ak1ibmcloud","secret":"@preset:misc.secret_here@","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:icos.bucket@","credentials":{"access_key_id":"@preset:icos.access_key@","secret_access_key":"@preset:icos.secret_key@"},"path":"/"}}'
	@$(STOP_TEST) $@
$(F)aocat9: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key create --cloud=aws --region=@preset:aws.region @json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:aws.bucket@","credentials":{"access_key_id":"@preset:aws.access_key@","secret_access_key":"@preset:aws.secret_key@"},"path":"/"}}'$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)aocat10: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key list --fields=name,id$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)aocat11: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key node ak1ibmcloud --secret=@preset:misc.secret_here browse /
	@$(STOP_TEST) $@
$(F)aocat13: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) --preset=aoc_admin aoc admin ats access_key delete ak1ibmcloud$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocts,$(F)aocat4 $(F)aocat5 $(F)aocat6 $(F)aocat7 $(F)aocat8 $(F)aocat9 $(F)aocat10 $(F)aocat11 $(F)aocat13))
#######################################################################################################################
$(DIR_TMP)wf_id: $(F)aocauto1
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow list --select=@json:'{"name":"test_workflow"}' --fields=id --format=csv --display=data --output=$@
$(F)aocauto1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow create @json:'{"name":"test_workflow"}'
	@$(STOP_TEST) $@
$(F)aocauto2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow list
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow list --query=@json:'{"show_org_workflows":"true"}' --scope=admin:all
	@$(STOP_TEST) $@
$(F)aocauto3: $(DIR_TMP)wf_id
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow action $$(cat $(DIR_TMP)wf_id) create @json:'{"name":"toto"}' \
		| tee action.info
	sed -nEe 's/^\| id +\| ([^ ]+) +\|/\1/p' action.info > tmp_action_id.txt
	rm -f action.info
	rm -f tmp_action_id.txt
	@$(STOP_TEST) $@
$(F)aocauto10: $(DIR_TMP)wf_id
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=aoc_admin aoc automation workflow delete $$(cat $(DIR_TMP)wf_id)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,taocauto,$(F)aocauto1 $(F)aocauto2 $(F)aocauto3 $(F)aocauto10))
#######################################################################################################################
taoc: taocgen taocf taocp taocadm taocts taocauto
clean_taoc: clean_taocgen clean_taocf clean_taocp clean_taocadm clean_taocts clean_taocauto
#######################################################################################################################
$(F)orch_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator health
	@$(STOP_TEST) $@
$(F)orch_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(CLI_TEST) orchestrator health --url=https://wrong.url --format=nagios$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)orch_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) config detect @preset:orch_user.url
	@$(STOP_TEST) $@
$(F)orch_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:orch_user.url orchestrator --username=test --password=test
	@$(STOP_TEST) $@
$(F)orch_info: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator info
	@$(STOP_TEST) $@
$(F)orch_wf_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow list
	@$(STOP_TEST) $@
$(F)orch_wf_sta: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow status ALL
	@$(STOP_TEST) $@
$(F)orch_wf_inp: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow inputs @preset:orch.workflow_id
	@$(STOP_TEST) $@
$(F)orch_wf_sti: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow status @preset:orch.workflow_id
	@$(STOP_TEST) $@
$(F)orch_wf_str1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow start @preset:orch.workflow_id @json:'{"Param":"world !"}'
	@$(STOP_TEST) $@
$(F)orch_wf_str2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow start @preset:orch.workflow_id @json:'{"Param":"world !"}' --result=ResultStep:Complete_status_message
	@$(STOP_TEST) $@
$(F)orch_plugins: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator plugins
	@$(STOP_TEST) $@
$(F)orch_processes: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator processes
	@$(STOP_TEST) $@
$(F)orch_wf_details: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) orchestrator workflow details @preset:orch.workflow_id
	$(INCMAN)$(CLI_TEST) orchestrator workflow export @preset:orch.workflow_id
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,torc,$(F)orch_health $(F)orch_health_bad $(F)orch_detect $(F)orch_wizard $(F)orch_info $(F)orch_wf_list $(F)orch_wf_sta $(F)orch_wf_inp $(F)orch_wf_sti $(F)orch_wf_str1 $(F)orch_wf_str2 $(F)orch_plugins $(F)orch_processes $(F)orch_wf_details))
#######################################################################################################################
$(F)at4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats cluster list
	@$(STOP_TEST) $@
$(F)at5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats cluster clouds
	@$(STOP_TEST) $@
$(F)at6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats cluster show --cloud=aws --region=eu-west-1
	@$(STOP_TEST) $@
$(F)at7: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats cluster show 1f412ae7-869a-445c-9c05-02ad16813be2
	@$(STOP_TEST) $@
$(F)at2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats api_key instances
	@$(STOP_TEST) $@
$(F)at1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats api_key list
	@$(STOP_TEST) $@
$(F)at3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats api_key create
	@$(STOP_TEST) $@
$(F)at8: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) ats access_key delete ak2ibmcloud$(END_IGN)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) ats access_key create --cloud=softlayer --region=@preset:icos.region @json:@extend:'{"id":"ak2ibmcloud","secret":"@preset:misc.secret_here@","name":"my test key","storage":{"type":"ibm-s3","bucket":"@preset:icos.bucket@","credentials":{"access_key_id":"@preset:icos.access_key@","secret_access_key":"@preset:icos.secret_key@"},"path":"/"}}'
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) ats access_key show ak2ibmcloud
	$(INCMAN)$(CLI_TEST) ats access_key entitlement ak2ibmcloud
	@$(STOP_TEST) $@
$(F)at9: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) ats access_key create --cloud=aws --region=@preset:aws.region @json:@extend:'{"id":"ak_aws","name":"my test key AWS","storage":{"type":"aws_s3","bucket":"@preset:aws.bucket@","credentials":{"access_key_id":"@preset:aws.access_key@","secret_access_key":"@preset:aws.secret_key@"},"path":"/"}}'$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)at10: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) ats access_key list --fields=name,id$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)at11: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats access_key node ak2ibmcloud browse / --secret=@preset:misc.secret_here
	@$(STOP_TEST) $@
$(F)at12: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) ats access_key cluster ak2ibmcloud --secret=@preset:misc.secret_here
	@$(STOP_TEST) $@
$(F)at13: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) ats access_key delete ak2ibmcloud$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(F)at14: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(BEG_FAI)$(CLI_TEST) ats access_key delete ak_aws$(END_FAI_HIDE)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tats,$(F)at4 $(F)at5 $(F)at6 $(F)at7 $(F)at2 $(F)at1 $(F)at3 $(F)at8 $(F)at9 $(F)at10 $(F)at11 $(F)at12 $(F)at13 $(F)at14))
#######################################################################################################################
$(F)nd_sync_pull_conf: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)nd_sync_pull_conf
	mkdir -p $(TMP_SYNCS)nd_sync_pull_conf
	$(INCMAN)$(CLI_TEST) node sync pull /aspera-test-dir-tiny --to-folder=$(TMP_SYNCS)nd_sync_pull_conf @json:'{"reset":true}'
	$(INCMAN)$(CLI_TEST) node sync admin status $(TMP_SYNCS)nd_sync_pull_conf
	@$(STOP_TEST) $@
$(F)nd_sync_v2: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -fr $(TMP_SYNCS)nd_sync_v2
	mkdir -p $(TMP_SYNCS)nd_sync_v2
	$(INCMAN)$(CLI_TEST) node sync pull /aspera-test-dir-tiny --to-folder=$(TMP_SYNCS)nd_sync_v2 @json:'{"name":"$(SYNC_NAME)","reset":true}'
	$(INCMAN)$(CLI_TEST) node sync admin status $(TMP_SYNCS)nd_sync_v2
	@$(STOP_TEST) $@
$(F)nd_async_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async list
	@$(STOP_TEST) $@
$(F)nd_async_show: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async show ALL
	$(INCMAN)$(CLI_TEST) node async show %name:$(SYNC_NAME)
	@$(STOP_TEST) $@
$(F)nd_async_cntr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async counters %name:$(SYNC_NAME)
	@$(STOP_TEST) $@
$(F)nd_async_bw: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async bandwidth %name:$(SYNC_NAME)
	@$(STOP_TEST) $@
$(F)nd_async_files: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async files %name:$(SYNC_NAME)
	$(INCMAN)$(CLI_TEST) node async files %name:$(SYNC_NAME) --once-only=yes
	@$(STOP_TEST) $@
$(F)nd_async_del: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node async delete ALL
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tnsync,$(F)nd_sync_pull_conf $(F)nd_sync_v2 $(F)nd_async_list $(F)nd_async_show $(F)nd_async_cntr $(F)nd_async_bw $(F)nd_async_files $(F)nd_async_del))
#######################################################################################################################
$(F)sync_create: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) server -Pserver2_user delete @preset:sync.remote_path$(END_IGN)
	$(CLI_TEST) server -Pserver2_user mkdir @preset:sync.remote_path
	$(BEG_IGN)$(CLI_TEST) node delete @preset:sync.local_path$(END_IGN)
	$(CLI_TEST) node mkdir @preset:sync.local_path
	$(CLI_TEST) node upload 'faux:///testfile1?1m' --to-folder=@preset:sync.local_path
	set -x&&\
	host_port=$$($(CLI_TEST) config preset get server2_user url|cut -f3 -d/)&&\
	host=$${host_port%:*}&&\
	port=$${host_port#*:}&&\
	$(INCMAN)$(CLI_TEST) node ssync create @json:@extend:'{"configuration":{"name":"my_node_sync","local":{"path":"@preset:sync.local_path_real@"},"remote":{"host":"'"$${host}"'","port":'"$${port}"',"user":"@preset:server_user.username@","pass":"@preset:server_user.password@","path":"@preset:sync.remote_path@"}}}'
	$(INCMAN)$(CLI_TEST) node ssync list
	@$(STOP_TEST) $@
$(F)sync_other: $(F)sync_create
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) node ssync start %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync show %name:my_node_sync
	sleep 30
	$(INCMAN)$(CLI_TEST) node ssync bandwidth %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync counters %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync files %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync state %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync stop %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync summary %name:my_node_sync
	$(INCMAN)$(CLI_TEST) node ssync delete %name:my_node_sync
	$(BEG_ERR)$(CLI_TEST) node ssync delete not_exist$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tnsyncs,$(F)sync_create $(F)sync_other))
#######################################################################################################################
$(F)conf_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:node_user.url
	$(BEG_ERR)$(CLI_TEST) config detect https://www.ibm.com$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)conf_ascp_show: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp show
	@$(STOP_TEST) $@
$(F)conf_ascp_spec: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp spec
	$(INCMAN)$(CLI_TEST) config sync spec
	$(CLI_TEST) config sync translate --format=jsonpp --show-secrets=yes -- -L "/optlogs/" \
 -N "transfer_test" -x \
 -P 33001 -k md5-sparse \
 -i "/root/.ssh/id_rsa_eudemo" \
 -b "/opt/async_db" \
 -d "/opt/source/" \
 -C --scan-interval=30 \
 --transfer-threads=1 \
 --pending-max=2000 \
 -r "/tmp/dest/" \
 --user root \
 --host 1.2.3.4 \
 -R "/tmp/logs/" \
 -B "/opt/async_db" \
 -l 1000 \
 --cooloff=5 \
 --preserve-uid --preserve-gid \
 -K push
	@$(STOP_TEST) $@
$(F)conf_ascp_schema: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp schema --format=jsonpp
	@$(STOP_TEST) $@
$(F)conf_ascp_errors: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp errors
	@$(STOP_TEST) $@
$(F)conf_ascp_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp products list
	$(INCMAN)$(CLI_TMP_CONF) config ascp products use 'IBM Aspera Connect'
	$(CLI_TMP_CONF) config ascp use $$(which ascp)
	@$(STOP_TEST) $@
$(F)conf_ascp_3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp connect list
	@$(STOP_TEST) $@
$(F)conf_ascp_4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp connect info 'Aspera Connect for Windows'
	@$(STOP_TEST) $@
$(F)conf_ascp_5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp connect version 'Aspera Connect for Windows' list
	@$(STOP_TEST) $@
$(F)conf_ascp_6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp connect version 'Aspera Connect for Windows' download 'Windows Installer' --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) config ascp connect version 'Aspera Connect for Windows' open documentation
	@$(STOP_TEST) $@
$(F)conf_ascp_install: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -fr "$$($(CLI_TEST) --show-config --fields=sdk_folder)"
	$(INCMAN)$(CLI_TEST) config ascp install 1.1.3
	$(INCMAN)$(CLI_TEST) config ascp install
	rm -fr $(DIR_TMP)sdk_test_dir
	$(INCMAN)$(CLI_TEST) config ascp install --sdk-folder=$(DIR_TMP)sdk_test_dir
	$(INCMAN)$(CLI_TEST) config transferd list
	$(INCMAN)$(CLI_TEST) config transferd install
	$(CLI_TEST) config transferd list --select=@json:'{"platform":"osx-arm64","version":"1.1.3"}' --fields=url | $(CLI_TEST) conf download @stdin: --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(F)conf_ascp_8: $(F)conf_ascp_install
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config ascp info --sdk-folder=$(DIR_TMP)sdk_test_dir
	@$(STOP_TEST) $@
$(F)conf_pset_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset set conf_name param value
	$(INCMAN)$(CLI_TMP_CONF) config preset unset conf_name param
	$(CLI_TEST) config preset lookup --url=@preset:faspex4_user.url --username=@preset:faspex4_user.username
	@$(STOP_TEST) $@
$(F)conf_pset_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset show conf_name
	@$(STOP_TEST) $@
$(F)conf_pset_3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset set default shares conf_name
	@$(STOP_TEST) $@
$(F)conf_pset_4: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset delete conf_name
	@$(STOP_TEST) $@
$(F)conf_pset_5: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset initialize conf_name @json:'{"p1":"v1","p2":"v2"}'
	@$(STOP_TEST) $@
$(F)conf_pset_6: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset update conf_name --p1=v1 --p2=v2
	@$(STOP_TEST) $@
$(F)conf_open: $(TMP_EXISTS)
	@$(START_TEST) $@
	@echo $@ open configuration file in text editor
	$(INCMAN)$(CLI_TMP_CONF) config open
	@$(STOP_TEST) $@
$(F)conf_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset list
	@$(STOP_TEST) $@
$(F)conf_over: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset overview
	@$(STOP_TEST) $@
$(F)conf_vers_check: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TMP_CONF) config preset set GLOBAL version_check_days 0
	@$(STOP_TEST) $@
$(F)conf_gem: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config gem path
	$(INCMAN)$(CLI_TEST) config gem version
	$(INCMAN)$(CLI_TEST) config gem name
	$(INCMAN)$(CLI_TEST) config folder
	$(INCMAN)$(CLI_TEST) config file
	$(INCMAN)$(CLI_TEST) config smtp_settings
	$(INCMAN)$(CLI_TMP_CONF) config initdemo
	@$(STOP_TEST) $@
$(F)conf_gem2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TMP_CONF) config initdemo
	$(CLI_TEST) config gem path --http-proxy=http://test1 --http-options=@json:'{"user_agent":"test1"}'
	$(CLI_TEST) config coffee --cert_stores=@ruby:'[OpenSSL::X509::DEFAULT_CERT_DIR,OpenSSL::X509::DEFAULT_CERT_FILE]' --http-options=@json:'{"ssl_options":["CIPHER_SERVER_PREFERENCE","-NETSCAPE_CA_DN_BUG"]}' --insecure=yes
	@$(STOP_TEST) $@
$(F)conf_vault_macos: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) -N config vault info --vault=@json:'{"type":"system"}'
	$(BEG_IGN)$(CLI_TEST) -N config vault create @json:'{"label":"foo"}' --vault=@json:'{"type":"system"}'$(END_IGN)
	$(CLI_TEST) -N config vault show foo --vault=@json:'{"type":"system"}'
	$(BEG_IGN)$(CLI_TEST) -N config vault delete foo --vault=@json:'{"type":"system"}'$(END_IGN)
	@$(STOP_TEST) $@
VAULT_FILE=$(shell realpath $(DIR_TOP))/tmp/sample_vault.bin
NEW_VAULT_PASS=my_other_pass_here
$(F)conf_vault_file: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -f $(VAULT_FILE) $(TEST_CONFIG)
	$(CLI_TMP_CONF) config preset set GLOBAL vault @json:'{"type":"file","file":"'"$(VAULT_FILE)"'"}'
	$(CLI_TMP_CONF) config preset set GLOBAL vault_password _simple_one_
	$(INCMAN)$(CLI_TMP_CONF) config vault create @json:'{"label":"my_label","password":"my_password_here","description":"my secret"}'
	$(INCMAN)$(CLI_TMP_CONF) config vault info
	$(INCMAN)$(CLI_TMP_CONF) config vault list
	$(INCMAN)$(CLI_TMP_CONF) config vault show my_label
	$(CLI_TMP_CONF) config preset ask my_preset <<< $$'username\npassword\n\nthe_user\nthe_pass\n'
	$(CLI_TMP_CONF) config preset secure my_preset
	$(CLI_TMP_CONF) config vault password $(NEW_VAULT_PASS)
	$(CLI_TMP_CONF) config preset set GLOBAL vault_password $(NEW_VAULT_PASS)
	$(INCMAN)$(CLI_TMP_CONF) config vault list
	$(INCMAN)$(CLI_TMP_CONF) config vault delete my_label
	$(INCMAN)$(CLI_TMP_CONF) config echo @vault:my_preset.password
	$(BEG_ERR)$(CLI_TMP_CONF) config echo @vault:bad$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TMP_CONF) config echo @vault:bad.password$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TMP_CONF) config echo @vault:my_preset.bad$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)conf_help_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) -h
	@$(STOP_TEST) $@
$(F)conf_help_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) --bash-comp
	@$(STOP_TEST) $@
$(F)conf_coffee_1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config coffee
	@$(STOP_TEST) $@
$(F)conf_coffee_2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config coffee --ui=text
	@$(STOP_TEST) $@
$(F)conf_coffee_3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config coffee --ui=text --image=@json:'{"text":true}'
	$(INCMAN)$(CLI_TEST) config coffee --ui=text --image=@json:'{"text":true,"double":false}'
	@$(STOP_TEST) $@
$(F)conf_image: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config image https://eudemo.asperademo.com/wallpaper.jpg
	@$(STOP_TEST) $@
# unset: to test like on Windows
$(F)conf_plugins: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config plugins list
	unset LC_ALL LC_CTYPE LANG && $(CLI_TEST) config plugins list
	$(INCMAN)$(CLI_TEST) config plugins create my_command $(DIR_TMP)
	$(CLI_TEST) my_command --plugin-folder=$(DIR_TMP)
	@$(STOP_TEST) $@
$(F)conf_genkey: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -f $(DIR_TMP)my_key $(DIR_TMP)my_key.pub
	$(INCMAN)$(CLI_TEST) config genkey $(DIR_TMP)my_key
	rm -f $(DIR_TMP)my_key $(DIR_TMP)my_key.pub
	$(INCMAN)$(CLI_TEST) config genkey $(DIR_TMP)my_key 4096
	$(INCMAN)$(CLI_TEST) config pubkey @file:$(DIR_TMP)my_key
	$(BEG_ERR)$(CLI_TEST) config genkey $(DIR_TMP)my_key not_int$(END_ERR_HIDE)
	@$(STOP_TEST) $@
$(F)conf_cert: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config remote_certificate name @preset:node_user.url
	$(INCMAN)$(CLI_TEST) config remote_certificate chain @preset:node_user.url
	$(INCMAN)$(CLI_TEST) config remote_certificate only @preset:node_user.url
	@$(STOP_TEST) $@
$(F)conf_smtp: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config email_test --notify-to=@preset:misc.email_external
	@$(STOP_TEST) $@
$(F)conf_pac: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config proxy_check --fpac=@file:$(DIR_TST)proxy.pac https://eudemo.asperademo.com --proxy-credentials=@list:,user,pass
	@$(STOP_TEST) $@
$(F)conf_check_gem: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config check_update
	rm -f $(CLI_HOME)persist_store/version_last_check.txt
	$(INCMAN)$(CLI_TEST) config check_update
	@$(STOP_TEST) $@
$(F)conf_doc: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config doc
	$(INCMAN)$(CLI_TEST) config doc transfer-parameters
	@$(STOP_TEST) $@
$(F)conf_echo: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config echo hello
	$(INCMAN)$(CLI_TEST) config echo @uri:/etc/hosts
	$(INCMAN)$(CLI_TEST) config echo @uri:file:/etc/hosts
	$(INCMAN)$(CLI_TEST) config echo @uri:http://ifconfig.me
	$(INCMAN)$(CLI_TEST) config echo @uri:https://ifconfig.me
	$(INCMAN)$(CLI_TEST) config echo @base64:SGVsbG8gV29ybGQK
	$(INCMAN)$(CLI_TEST) config echo @list:,1,2,3
	$(INCMAN)$(CLI_TEST) config echo @env:USER
	$(INCMAN)$(CLI_TEST) config echo -- --special-string
	$(INCMAN)$(CLI_TEST) config echo @json:'[{"user":{"id":1,"name":"foo"},"project":"bar"}]' --multi-single=yes
	$(INCMAN)$(CLI_TEST) config echo @json:'[{"user":{"id":1,"name":"foo"},"project":"bar"}]' --multi-single=single
	$(INCMAN)$(CLI_TEST) config echo '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="50" fill="#006699"/></svg>' --format=image
	$(BEG_ERR)$(CLI_TEST) config echo @file:no_such_file$(END_ERR_HIDE)
	$(BEG_ERR)$(CLI_TEST) config echo @json:'{"ok":1,"bad":mauvais}'$(END_ERR_SHOW)
	echo $$'1\n2\n3'|$(INCMAN)$(CLI_TEST) config echo @lines:@stdin:
	echo $$'1\n2\n3'|$(INCMAN)$(CLI_TEST) config echo @stdbin:
	echo $$'t1,t2,t3\na,b,d\nd,e,f'|$(INCMAN)$(CLI_TEST) config echo @csvt:@stdin:
	ruby -rzlib -e'puts Zlib::Deflate.deflate("Hello World")'|$(INCMAN)$(CLI_TEST) config echo @zlib:@stdin:
	set -xe&&\
	for f in text ruby json jsonpp yaml table csv;do \
	  $(CLI_TEST) config echo @json:'{"user1":"yes","user2":"no"}' --format=$$f;\
	done
	$(CLI_TEST) config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --format=csv --table=@json:'{"headers":true,"force_quotes":true}'
	$(CLI_TEST) config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --fields=@json:'["id"]'
	$(CLI_TEST) config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --fields=@re:'i+'
	$(CLI_TEST) config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --fields=@ruby:'->(f){f.eql?("id")}'
	$(CLI_TEST) config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --select=@ruby:'->(r){r["id"].eql?(8)}'
	@$(STOP_TEST) $@
$(F)conf_extended: $(TMP_EXISTS)
	@$(START_TEST) $@
	test $$($(CLI_TEST) config echo @val:@file:foo --format=text) = @file:foo
	test $$($(CLI_TEST) config echo @base64:Zm9v --format=text) = foo
	test "$$($(CLI_TEST) config echo @lines:@json:'"1\n2\n"' --format=ruby)" = '["1", "2"]'
	test "$$($(CLI_TEST) config echo @list:,1,2 --format=ruby)" = '["1", "2"]'
	test "$$($(CLI_TEST) config echo @json:'["1","2"]' --format=ruby)" = '["1", "2"]'
	test "$$($(CLI_TEST) config echo @yaml:@json:'"- 1\n- 2\n"' --format=ruby)" = '[1, 2]'
	@$(STOP_TEST) $@
$(F)conf_interactive: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config echo @secret:
	@$(STOP_TEST) $@
$(F)conf_hint: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(CLI_TEST) config test throw Aspera::RestCallError   'Signature has expired'$(END_ERR_SHOW)
	$(BEG_ERR)$(CLI_TEST) config test throw Aspera::Transfer::Error 'Remote host is not who we expected'$(END_ERR_SHOW)
	$(BEG_ERR)$(CLI_TEST) config test throw OpenSSL::SSL::SSLError  'does not match the server certificate'$(END_ERR_SHOW)
	$(BEG_ERR)$(CLI_TEST) config test throw OpenSSL::SSL::SSLError  'certificate verify failed'$(END_ERR_SHOW)
	$(BEG_ERR)$(CLI_TEST) config test throw OpenSSL::PKey::RSAError 'Neither PUB key nor PRIV key'$(END_ERR_SHOW)
	@$(STOP_TEST) $@
$(F)conf_logger: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config file --log-level=debug --logger=syslog
	$(INCMAN)$(CLI_TEST) config file --log-level=debug --log-format=standard
	$(INCMAN)$(CLI_TEST) config file --log-level=debug --log-format=default
	$(INCMAN)$(CLI_TEST) config coffee --log-level=trace2 --log-format=caller
	$(INCMAN)$(CLI_TEST) config file --log-level=debug --log-format=@ruby:'->(s, d, p, m){"#{d.strftime("%Y-%m-%d %H:%M:%S")} - #{p} - #{s} - #{m}\n"}'
	$(CLI_TEST) config echo @ruby:'%i[trace2 trace1 debug info warn error fatal unknown].each{|i|Log.log.send(i,"<"*80)};"ok"' --log-level=trace2
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tconfig,$(F)conf_detect $(F)conf_ascp_show $(F)conf_ascp_spec $(F)conf_ascp_schema $(F)conf_ascp_errors $(F)conf_ascp_2 $(F)conf_ascp_3 $(F)conf_ascp_4 $(F)conf_ascp_5 $(F)conf_ascp_6 $(F)conf_ascp_install $(F)conf_ascp_8 $(F)conf_pset_1 $(F)conf_pset_2 $(F)conf_pset_3 $(F)conf_pset_4 $(F)conf_pset_5 $(F)conf_pset_6 $(F)conf_open $(F)conf_list $(F)conf_over $(F)conf_vers_check $(F)conf_gem $(F)conf_gem2 $(F)conf_help_1 $(F)conf_help_2 $(F)conf_coffee_1 $(F)conf_coffee_2 $(F)conf_plugins $(F)conf_genkey $(F)conf_cert $(F)conf_smtp $(F)conf_pac $(F)conf_check_gem $(F)conf_doc $(F)conf_echo $(F)conf_extended $(F)conf_hint $(F)conf_logger))
#######################################################################################################################
$(F)prev_check: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview check --skip-types=office
	@$(STOP_TEST) $@
$(F)prev_dcm: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview test --base=$(DIR_TMP)$$(basename $@) @preset:file.dcm
	@$(STOP_TEST) $@
$(F)prev_dcm_mm: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview test --mimemagic=yes --base=$(DIR_TMP)$$(basename $@) @preset:file.dcm
	@$(STOP_TEST) $@
$(F)prev_jpg_unk_mm: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview test --mimemagic=yes --base=$(DIR_TMP)$$(basename $@) @preset:file.jpg_unk
	@$(STOP_TEST) $@
$(F)prev_mxf_blend: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview test --base=$(DIR_TMP)$$(basename $@) @preset:file.mxf mp4 --video-conversion=blend --query=@json:'{"text":true,"double":true}'
	@$(STOP_TEST) $@
$(F)prev_pdf: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.pdf
	@$(STOP_TEST) $@
$(F)prev_txt: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) /etc/hosts
	@$(STOP_TEST) $@
$(F)prev_docx: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.docx
	@$(STOP_TEST) $@
$(F)prev_mpg_png_fix: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg --video-png-conv=fixed
	@$(STOP_TEST) $@
$(F)prev_mpg_png_ani: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg --video-png-conv=animated
	@$(STOP_TEST) $@
$(F)prev_mpg_reencode: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg mp4 --video-conversion=reencode
	@$(STOP_TEST) $@
$(F)prev_mpg_clips: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview show --base=$(DIR_TMP)$$(basename $@) @preset:file.mpg mp4 --video-conversion=clips
	@$(STOP_TEST) $@
$(F)prev_trevents: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) --preset=preview_ak node upload @preset:file.mxf @preset:file.docx --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none"}'
	sleep 4
	$(INCMAN)$(CLI_TEST) preview trevents --once-only=yes --skip-types=office --log-level=info
	@$(STOP_TEST) $@
$(F)prev_events: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) --preset=preview_ak node upload @preset:file.mxf @preset:file.docx --ts=@json:'{"target_rate_kbps":1000000,"resume_policy":"none"}'
	sleep 4
	$(INCMAN)$(CLI_TEST) preview events --once-only=yes --skip-types=office --log-level=info
	@$(STOP_TEST) $@
$(F)prev_scan: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview scan --skip-types=office --log-level=info --skip-folder=foo 
	$(CLI_TEST) preview scan --skip-folder=foo --skip-folder=bar --skip-folder=@list:,1,2
	@$(STOP_TEST) $@
$(F)prev_folder: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) preview scan --scan-id=1 --skip-types=office --log-level=info --file-access=remote --ts=@json:'{"target_rate_kbps":1000000}'
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tprev,$(F)prev_check $(F)prev_dcm $(F)prev_pdf $(F)prev_txt $(F)prev_docx $(F)prev_mpg_png_fix $(F)prev_mpg_png_ani $(F)prev_mxf_blend $(F)prev_mpg_reencode $(F)prev_mpg_clips $(F)prev_trevents $(F)prev_events $(F)prev_scan $(F)prev_folder))
#######################################################################################################################
# TODO : finalize
thot:
	rm -fr source_hot
	mkdir source_hot
	$(BEG_IGN)$(CLI_TEST) server delete @extend:@preset:server.upload_folder@/target_hot$(END_IGN)
	$(INCMAN)$(CLI_TEST) server mkdir @extend:@preset:server.upload_folder@/target_hot
	echo hello > source_hot/new_file
	$(INCMAN)$(CLI_TEST) server upload --to-folder=@extend:@preset:server.upload_folder@/target_hot --lock-port=12345 --transfer-info=@json:'{"ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(INCMAN)$(CLI_TEST) server browse @extend:@preset:server.upload_folder@/target_hot
	ls -al source_hot
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) server upload --to-folder=@extend:@preset:server.upload_folder@/target_hot --lock-port=12345 --transfer-info=@json:'{"ascp_args":["--remove-after-transfer","--remove-empty-directories","--exclude-newer-than=-8","--src-base","source_hot"]}' source_hot
	$(INCMAN)$(CLI_TEST) server browse @extend:@preset:server.upload_folder@/target_hot
	ls -al source_hot
	rm -fr source_hot
	@$(STOP_TEST) $@
#######################################################################################################################
$(F)tcos_info1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) cos node info -N --bucket=@preset:icos.bucket --region=@preset:icos.region --service-credentials=@json:@file:@preset:file.cos_svc_cred
	@$(STOP_TEST) $@
$(F)tcos_info2: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) cos node info -N --bucket=@preset:icos.bucket --endpoint=@preset:icos.endpoint --apikey=@preset:icos.api_key --crn=@preset:icos.resource_instance_id
	@$(STOP_TEST) $@
$(F)tcos_info3: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) cos node info --log-level=trace2
	@$(STOP_TEST) $@
$(F)tcos_show: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_IGN)$(CLI_TEST) cos node access_key show self$(END_IGN)
	@$(STOP_TEST) $@
$(F)tcos_upload: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) cos node upload $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)tcos_download: $(F)tcos_upload
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) cos node download $(TST_ASC_FILENAME) --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tcos,$(F)tcos_info1 $(F)tcos_info2 $(F)tcos_info3 $(F)tcos_show $(F)tcos_upload $(F)tcos_download))
#######################################################################################################################
$(F)f5_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 health -N --url=@preset:faspex5_user.url
	@$(STOP_TEST) $@
$(F)f5_health_bad: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) faspex5 health --url=https://www.ibm.com
	@$(STOP_TEST) $@
$(F)f5_health_nagios: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(CLI_TEST) faspex5 health -N --url=https://www.ibm.com --format=nagios$(END_ERR_SHOW)
	@$(STOP_TEST) $@
$(F)f5_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:faspex5_user.url faspex5
	@$(STOP_TEST) $@
$(F)f5_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:faspex5_user.url faspex5 --key-path=@preset:file.private_key --preset=faspex5_user
	$(CLI_WIZ_TEST) config wizard @preset:faspex5_user.url faspex5 --key-path=@preset:file.private_key --url= --username=a@b.c
	$(CLI_WIZ_TEST) config wizard https://eudemo.asperademo.com faspex5 --username=admin@ibm.com --key-path= --show-secrets=yes --client-id=abc --client-secret=abc
	$(BEG_ERR)$(CLI_TEST) config detect https://eudemo.asperademo.com:22 faspex5$(END_ERR_HIDE)
	$(INCMAN)$(CLI_TEST) -N config detect @preset:faspex5_user.url
	$(CLI_TEST) config detect @preset:faspex5_user.url
	@$(STOP_TEST) $@
$(F)f5_version: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 version
	@$(STOP_TEST) $@
$(F)f5_pack_rcv_init: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages receive INIT --once-only=yes
	@$(STOP_TEST) $@
$(F)f5_p1: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send @json:@extend:'{"title":"test title","recipients":[{"name":"@preset:faspex5_user.username@"}]@preset:faspex5.meta@}' $(TST_ASC_LCL_PATH) --ts=@json:'{"content_protection_password":"my_secret_here"}'
	@$(STOP_TEST) $@
$(F)f5_pack_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages list --query=@json:'{"mailbox":"inbox","status":"completed"}'
	$(INCMAN)$(CLI_TEST) faspex5 packages list --box=ALL --preset=f5_admin
	$(INCMAN)$(CLI_TEST) faspex5 packages list --box=outbox --fields=DEF,sender.email,recipients.0.recipient_type
	@$(STOP_TEST) $@
$(F)f5_sh_folder_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 shared_folders list
	@$(STOP_TEST) $@
$(F)f5_sh_folder_br: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 shared_folders browse @extend:%name:@preset:faspex5.shared_folder_name@
	@$(STOP_TEST) $@
$(F)f5_sh_folder_send: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send --shared-folder=@extend:%name:@preset:faspex5.shared_folder_name@ @json:@extend:'{"title":"test title","recipients":["@preset:misc.email_internal@"]}' @preset:faspex5.shared_folder_file --fields=id --display=data --output=$(STATE)f5_pack_id
	@echo "Sent package with id: $$(cat $(STATE)f5_pack_id)"
	$(CLI_TEST) faspex5 packages status $$(cat $(STATE)f5_pack_id) @list:,failed,completed
	@$(STOP_TEST) $@
$(F)f5_p3: $(F)f5_sh_folder_send
	@$(START_TEST) $@
	$(CLI_TEST) faspex5 packages list --query=@json:'{"status":"completed","max":1}' --fields=id --output=$(STATE)f5_pack_id
	$(INCMAN)$(CLI_TEST) faspex5 packages show $$(cat $(STATE)f5_pack_id)
	$(INCMAN)$(CLI_TEST) faspex5 packages status $$(cat $(STATE)f5_pack_id)
	$(INCMAN)$(CLI_TEST) faspex5 packages browse $$(cat $(STATE)f5_pack_id) --query=@json:'{"recursive":true}'
	$(INCMAN)$(CLI_TEST) faspex5 packages receive $$(cat $(STATE)f5_pack_id) --to-folder=$(DIR_TMP). --ts=@json:'{"content_protection_password":"my_secret_here"}'
	$(INCMAN)$(CLI_TEST) faspex5 packages receive ALL --once-only=yes --to-folder=$(DIR_TMP).
	$(INCMAN)$(CLI_TEST) faspex5 packages delete $$(cat $(STATE)f5_pack_id)
	@$(STOP_TEST) $@
$(F)f5_pack_shbox: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:faspex5.shared_box_name@"],"metadata":{"Options":"Opt1","TextInput":"example text"}}' $(TST_ASC_LCL_PATH)
	echo "Waiting for package to be available" && sleep 30
	$(INCMAN)$(CLI_TEST) faspex5 packages list --box=@preset:faspex5.shared_box_name
	$(CLI_TEST) faspex5 packages list --box=@preset:faspex5.shared_box_name --query=@json:'{"status":"completed","limit":1,"max":1}' --fields=id --format=csv --display=data --output=$(STATE)package_box_id1
	$(INCMAN)$(CLI_TEST) faspex5 packages show --box=@preset:faspex5.shared_box_name $$(cat $(STATE)package_box_id1)
	$(INCMAN)$(CLI_TEST) faspex5 packages receive --box=@preset:faspex5.shared_box_name $$(cat $(STATE)package_box_id1) --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(F)f5_pack_shbox_public: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send -N --url=@preset:faspex5.public_link_send_shared_box @json:@extend:'{"title":"test title"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)f5_pack_user_public: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send -N --url=@preset:faspex5.public_link_send_f5_user @json:@extend:'{"title":"test title"}' $(TST_ASC_LCL_PATH)
	@$(STOP_TEST) $@
$(F)f5_pack_wrkgrp: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 packages send @json:@extend:'{"title":"test title","recipients":["@preset:faspex5.workgroup@"]}' $(TST_ASC_LCL_PATH)
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) faspex5 packages list --box=@preset:faspex5.workgroup --group-type=workgroups
	$(CLI_TEST) faspex5 packages list --box=@preset:faspex5.workgroup --group-type=workgroups --query=@json:'{"status":"completed","limit":1,"max":1}' --fields=id --format=csv --display=data --output=$(STATE)workgroup_package_id1
	$(INCMAN)$(CLI_TEST) faspex5 packages show --box=@preset:faspex5.workgroup --group-type=workgroups $$(cat $(STATE)workgroup_package_id1)
	$(INCMAN)$(CLI_TEST) faspex5 packages receive --box=@preset:faspex5.workgroup --group-type=workgroups $$(cat $(STATE)workgroup_package_id1) --to-folder=$(DIR_TMP).
	@$(STOP_TEST) $@
$(F)f5_sh_fold: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 shared list
	$(INCMAN)$(CLI_TEST) faspex5 shared browse %name:@preset:faspex4.src
	@$(STOP_TEST) $@
$(F)f5_user_res: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 bearer_token
	$(INCMAN)$(CLI_TEST) faspex5 admin contacts list
	$(INCMAN)$(CLI_TEST) faspex5 admin workgroups list
	$(INCMAN)$(CLI_TEST) faspex5 admin shared_inboxes list 
	$(INCMAN)$(CLI_TEST) faspex5 admin workgroups list
	$(INCMAN)$(CLI_TEST) faspex5 admin saml_configs list
	$(INCMAN)$(CLI_TEST) faspex5 admin metadata_profiles list
	$(INCMAN)$(CLI_TEST) faspex5 admin configuration show
	@$(STOP_TEST) $@
$(F)f5_dist_list: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 admin distribution_lists list --query=@json:'{"type":"global"}'
	$(INCMAN)$(CLI_TEST) faspex5 admin distribution_lists create @json:'{"name":"test4","contacts":[{"name":"john@example.com"}]}'
	$(TEMPORIZE_CREATE)
	$(INCMAN)$(CLI_TEST) faspex5 admin distribution_lists delete %name:test4
	@$(STOP_TEST) $@
$(F)f5_adm_acc_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin accounts list
	@$(STOP_TEST) $@
$(F)f5_adm_job_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin jobs list --query=@json:'{"job_type":"email","status":"failed"}' --fields=id,error_desc
	@$(STOP_TEST) $@
$(F)f5_adm_nod_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node list 
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node show %name:Local
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node browse %name:Local
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node shared_folders %name:Local list
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node shared_folders %name:Local show %name:Main
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin node shared_folders %name:Local user %name:Main list
	@$(STOP_TEST) $@
$(F)f5_adm_api_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin oauth_clients list
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin alternate_addresses list
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin email_notifications list
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin email_notifications show welcome_email
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin configuration modify @json:'{"mfa_required":false}'
	@$(STOP_TEST) $@
$(F)f5_adm_reg_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin registrations list
	@$(STOP_TEST) $@
$(F)f5_adm_sbx_lst: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes list --query=@json:'{"all":true}'
	@$(STOP_TEST) $@
$(F)f5_adm_sbx_mem: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes members @extend:%name:@preset:faspex5.shared_box_name@ list
	@$(STOP_TEST) $@
$(F)f5_adm_sbx_cr: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes members @extend:%name:@preset:faspex5.shared_box_name@ create %name:john@example.com
	@$(STOP_TEST) $@
$(F)f5_adm_sbx_del: $(F)f5_adm_sbx_cr
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes members @extend:%name:@preset:faspex5.shared_box_name@ delete %name:john@example.com
	@$(STOP_TEST) $@
$(F)f5_adm_evt_app: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin event app --query=@json:'{"max":20}'
	@$(STOP_TEST) $@
$(F)f5_adm_evt_web: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin event web
	-$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes invite @extend:%name:@preset:faspex5.shared_box_name@ johnny@example.com
	-$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin shared_inboxes members @extend:%name:@preset:faspex5.shared_box_name@ delete %name:johnny@example.com
	@$(STOP_TEST) $@
$(F)f5_clean_del: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin clean_deleted
	@$(STOP_TEST) $@
$(F)f5_smtp: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(BEG_ERR)$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin smtp create @json:'{"auth_type":"open","server_address":"smtp.gmail.com","server_port":587,"domain":"gmail.com","tls_enabled":true,"packages_recipient_from":"sender"}'$(END_ERR_SHOW)
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin smtp modify @json:'{"default_time_zone_offset":"0"}'
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin smtp show
	$(INCMAN)$(CLI_TEST) --preset=f5_admin faspex5 admin smtp test @preset:misc.email_external
	@$(STOP_TEST) $@
$(F)f5_user: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 user account
	$(INCMAN)$(CLI_TEST) faspex5 user account --query.expand=true
	$(INCMAN)$(CLI_TEST) faspex5 user profile show
	$(INCMAN)$(CLI_TEST) faspex5 user profile modify @json:'{"preference":{"connect_disabled":false}}'
	@$(STOP_TEST) $@
$(F)f5_invite: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspex5 invitations create @json:'{"email_address":"aspera.user1+u@gmail.com"}'
	$(INCMAN)$(CLI_TEST) faspex5 invitation list
	$(CLI_TEST) faspex5 invitation list --fields=id --display=data --format=csv | $(CLI_TEST) faspex5 invitation delete --bulk=yes @lines:@stdin:
	@$(STOP_TEST) $@
$(F)f5_webauth: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) --preset=f5_web faspex5 version
	@$(STOP_TEST) $@
$(F)f5_fxgw: $(TMP_EXISTS)
	@$(START_TEST) $@
	rm -f $(DIR_TMP)pid_f5_fxgw
	$(INCMAN)$(CLI_TEST) faspex5 gateway --pid-file=$(DIR_TMP)pid_f5_fxgw @json:'{"url":"https://localhost:12346/aspera/faspex"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_fxgw;do sleep 1;let --i;done
	kill -0 $$(cat $(DIR_TMP)pid_f5_fxgw)
	$(CLI_TEST) -N faspex --url=https://localhost:12346/aspera/faspex --username=_unused_ --password=_unused_ package send --delivery-info=@json:'{"recipients":["laurent.martin.aspera@fr.ibm.com"],"title":"gateway aoc"}' 'faux:///test1?1m'
	-curl -k https://localhost:12346/aspera/faspex/send -d 'bad'
	-curl -k https://localhost:12346/aspera/faspex/bad -d 'bad'
	kill -TERM $$(cat $(DIR_TMP)pid_f5_fxgw)
	let i=10;while test $$i -gt 0 -a -f $(DIR_TMP)pid_f5_fxgw;do sleep 1;let --i;done
	@$(STOP_TEST) $@
$(F)f5_postproc: $(TMP_EXISTS)
	@$(START_TEST) $@
	-kill -TERM $$(cat $(DIR_TMP)pid_f5_postproc)
	rm -f $(DIR_TMP)pid_f5_postproc
	openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes -keyout $(DIR_TMP)key.pem -out $(DIR_TMP)cert.pem -subj "/CN=localhost"
	openssl pkcs12 -export -out $(DIR_TMP)localhost.p12 -inkey $(DIR_TMP)key.pem -in $(DIR_TMP)cert.pem -passout pass:changeit
	$(INCMAN)$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_postproc @json:'{"url":"https://localhost:8553/asclihook","script_folder":"$(DIR_TST)","cert":"$(DIR_TMP)localhost.p12","key":"changeit"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_postproc;do sleep 1;let --i;done
	kill -0 $$(cat $(DIR_TMP)pid_f5_postproc)&&echo ">>>> Process $$(cat $(DIR_TMP)pid_f5_postproc)"
	$(CLI_TEST) faspex5 packages send @json:@extend:'{"title":"test_webhook_ascli","recipients":["@preset:faspex5.shared_box_name@"]}' 'faux:///test1?1m'
	-curl -k https://localhost:8553/asclihook/post_proc_test.sh -d '{"faspex_pkg_directory":"/package test - 61ae5292-d8ef-496e-8b15-8cdc0379fc4a.aspera-package/PKG - package test","faspex_pkg_name":"Test files","faspex_pkg_note":"","faspex_pkg_id":506,"faspex_pkg_delivery_id":506,"faspex_recipient_list":"aspera-recipient-test@ibm.com","faspex_recipient_count":1,"faspex_sender_id":30,"faspex_sender_name":"aspera-sender-test@ibm.com","faspex_sender_email":"aspera-sender-test@ibm.com","faspex_pkg_total_bytes":4633,"faspex_pkg_total_files":1,"faspex_pkg_uuid":"61ae5299-d8ea-496e-8b15-8cdc0379fc4a","faspex_metadata_fields": "{\"_pkg_uuid\":\"61ae5292-d8ef-496e-8b15-8cdc0379fc4a\",\"_pkg_name\":\"Test files\",\"_created_utc\":\"2022-1209T17:47:03.545Z\"}","faspex_recipient_0":"aspera-sender-test@ibm.com"}'
	-curl -k https://localhost:8553/wrong -d '{}'
	sleep 5
	kill -TERM $$(cat $(DIR_TMP)pid_f5_postproc)
	let i=10;while test $$i -gt 0 -a -f $(DIR_TMP)pid_f5_postproc;do sleep 1;let --i;done
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_postproc @json:'{"url":"https://localhost:8553/asclihook","script_folder":"$(DIR_TST)","key":"$(DIR_TMP)key.pem"}' & sleep 5
	kill -TERM $$(cat $(DIR_TMP)pid_f5_postproc)
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_postproc @json:'{"url":"https://localhost:8553/asclihook","script_folder":"$(DIR_TST)","cert":"$(DIR_TMP)cert.pem","key":"$(DIR_TMP)key.pem"}' & sleep 5
	kill -TERM $$(cat $(DIR_TMP)pid_f5_postproc)
	@$(STOP_TEST) $@
PKCS_P=YourExportPassword
$(F)f5_cert_test: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_cert_test @json:'{"url":"http://localhost:18080/domain","script_folder":"$(DIR_TST)"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_cert_test;do sleep 1;let --i;done
	kill $$(cat $(DIR_TMP)pid_f5_cert_test)
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_cert_test @json:'{"url":"https://localhost:18443/domain","certificate":{},"script_folder":"$(DIR_TST)"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_cert_test;do sleep 1;let --i;done
	kill $$(cat $(DIR_TMP)pid_f5_cert_test)
	openssl req -newkey rsa:2048 -x509 -days 365 -nodes -keyout $(DIR_TMP)private_key.pem -out $(DIR_TMP)certificate.pem -subj "/CN=MyCert"
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_cert_test @json:'{"url":"https://localhost:18443/domain","certificate":{"cert":"$(DIR_TMP)certificate.pem","chain":"$(DIR_TMP)certificate.pem","key":"$(DIR_TMP)private_key.pem"},"script_folder":"$(DIR_TST)"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_cert_test;do sleep 1;let --i;done
	kill $$(cat $(DIR_TMP)pid_f5_cert_test)
	openssl pkcs12 -export -out $(DIR_TMP)certificate.p12 -inkey $(DIR_TMP)private_key.pem -in $(DIR_TMP)certificate.pem -name "MyCertAlias" -passout pass:$(PKCS_P)
	$(CLI_TEST) faspex5 postprocessing --pid-file=$(DIR_TMP)pid_f5_cert_test @json:'{"url":"https://localhost:18443/domain","certificate":{"pkcs12":"$(DIR_TMP)certificate.p12","key":"$(PKCS_P)"},"script_folder":"$(DIR_TST)"}' &
	let i=10;while test $$i -gt 0 -a ! -f $(DIR_TMP)pid_f5_cert_test;do sleep 1;let --i;done
	kill $$(cat $(DIR_TMP)pid_f5_cert_test)
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tf5,$(F)f5_health $(F)f5_health_bad $(F)f5_health_nagios $(F)f5_detect $(F)f5_wizard $$(F)f5_version $(F)f5_pack_rcv_init $(F)f5_p1 $(F)f5_pack_list $(F)f5_p3 $(F)f5_sh_folder_list $(F)f5_sh_folder_br $(F)f5_sh_folder_send $(F)f5_pack_shbox $(F)f5_pack_shbox_public $(F)f5_pack_user_public $(F)f5_pack_wrkgrp $(F)f5_user_res $(F)f5_dist_list $(F)f5_adm_acc_lst $(F)f5_adm_job_lst $(F)f5_adm_nod_lst $(F)f5_adm_api_lst $(F)f5_adm_reg_lst $(F)f5_adm_sbx_lst $(F)f5_adm_sbx_mem $(F)f5_adm_sbx_cr $(F)f5_adm_sbx_del $(F)f5_adm_evt_app $(F)f5_adm_evt_web $(F)f5_clean_del $(F)f5_smtp $(F)f5_user $(F)f5_invite $(F)f5_fxgw $(F)f5_sh_fold $(F)f5_postproc $(F)f5_cert_test))
#######################################################################################################################
$(F)httpgw_nagios: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) httpgw health
	@$(STOP_TEST) $@
$(F)httpgw_info: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) httpgw info
	@$(STOP_TEST) $@
$(F)httpgw_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:tst_httpgw.url httpgw
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,thgw,$(F)httpgw_nagios $(F)httpgw_info $(F)httpgw_detect))
#######################################################################################################################
$(F)faspio_health: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspio health
	@$(STOP_TEST) $@
$(F)faspio_detect: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) config detect @preset:tst_faspio.url faspio
	@$(STOP_TEST) $@
$(F)faspio_wizard: $(WIZ_DEPS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_WIZ_TEST) config wizard @preset:tst_faspio.url faspio  --username=@preset:tst_faspio.username --password=@preset:tst_faspio.password
	@$(STOP_TEST) $@
$(F)faspio_blist: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspio bridges list
	@$(STOP_TEST) $@
$(F)faspio_bcreate: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspio bridges create @json:'{"name":"test1","local":{"protocol":"tcp","tls_enabled":false,"port":"3000","bind_address":"127.0.0.1"},"forward":{"protocol":"fasp","tls_enabled":false,"port":"3994","bind_address":"127.0.0.1","host":["10.0.0.1"]}}'
	@$(STOP_TEST) $@
$(F)faspio_bclean: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) faspio bridges list --fields=id --format=json | $(INCMAN)$(CLI_TEST) faspio bridges delete --bulk=yes @json:@stdin:
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,tfio,$(F)faspio_health $(F)faspio_detect $(F)faspio_wizard $(F)faspio_blist $(F)faspio_bcreate $(F)faspio_bclean))
#######################################################################################################################
$(F)alee_nagios: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) alee health -N
	@$(STOP_TEST) $@
$(F)alee_entitlement: $(TMP_EXISTS)
	@$(START_TEST) $@
	$(INCMAN)$(CLI_TEST) alee entitlement
	@$(STOP_TEST) $@
$(eval $(call test_suite_all,alee,$(F)alee_nagios $(F)alee_entitlement))
