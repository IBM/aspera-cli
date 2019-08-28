NODE_PASS=Aspera123_
MY_CLIENT_ID=BMDiAWLP6g
MY_PRIVATE_KEY_FILE=$(TOOLCONFIGDIR)/filesapikey
#HSTS_ADDR=10.25.0.8
#FASPEX_ADDR=10.25.0.3
HSTS_ADDR=eudemo.asperademo.com
HSTS_SSH_URL=ssh://$(HSTS_ADDR):33001
HSTS_NODE_URL=https://$(HSTS_ADDR):9092
FASPEX_ADDR=$(HSTS_ADDR)
FASPEX_URL=https://$(FASPEX_ADDR)/aspera/faspex
FASPEX_SSH_URL=ssh://$(FASPEX_ADDR):33001
FASPEX_PUBLINK_RECV_PACKAGE=https://eudemo.asperademo.com/aspera/faspex/external_deliveries/121?passcode=581e505ea4d35771ee4444b6d933c3b333881c58&expiration=MjAxOS0wNi0xNlQwODozMjozN1o=
FASPEX_PUBLINK_SEND_DROPBOX=https://eudemo.asperademo.com/aspera/faspex/external/dropbox_submissions/new?passcode=acc3c37c608072dff8a3d09c6ad2154482b82e5e
FASPEX_PUBLINK_SEND_TO_USER=https://eudemo.asperademo.com/aspera/faspex/external/submissions/new?passcode=81c8c1df6f21e976e5b78389fa31bb1530e4c480
SERVER_FOLDER_UPLOAD=/Upload

TEST_SHARE=Upload
TEST_NODE_USER=node_asperaweb
TEST_NODE_PASS=demoaspera

TEST_WORKFLOW_ID=894

AOC_PUBLINK_RECV_PACKAGE=https://sedemo.ibmaspera.com/packages/public/receive?token=cpDktbNc8aHnyrbI_V49GzFwm5q3jxWnT_cDOjaewrc
AOC_PUBLINK_SEND_DROPBOX=https://aspera.pub/xxktoFw/Team_Inbox
AOC_PUBLINK_SEND_USER=https://aspera.pub/Nb4Ui_c
AOC_PUBLINK_FOLDER=https://aspera.pub/_5VG0jg



SAMPLE_FILENAME=200KB.1
CLIENT_DEMOFILE_PATH=~/Documents/Samples/$(SAMPLE_FILENAME)
