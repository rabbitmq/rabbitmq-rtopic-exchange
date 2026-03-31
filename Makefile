PROJECT = rabbitmq_rtopic_exchange
PROJECT_DESCRIPTION = Reverse Topic Exchange Type
PROJECT_VERSION = 4.2.5

RABBITMQ_VERSION ?= v4.2.x
current_rmq_ref = $(RABBITMQ_VERSION)

define PROJECT_APP_EXTRA_KEYS
	{broker_version_requirements, ["4.2.0"]}
endef

dep_amqp_client                = git_rmq-subfolder rabbitmq-erlang-client $(current_rmq_ref)
dep_rabbit_common              = git_rmq-subfolder rabbitmq-common $(current_rmq_ref)
dep_rabbit                     = git_rmq-subfolder rabbitmq-server $(current_rmq_ref)
dep_rabbitmq_ct_client_helpers = git_rmq-subfolder rabbitmq-ct-client-helpers $(current_rmq_ref)
dep_rabbitmq_ct_helpers        = git_rmq-subfolder rabbitmq-ct-helpers $(current_rmq_ref)

DEPS = rabbit_common rabbit
TEST_DEPS = rabbitmq_ct_helpers rabbitmq_ct_client_helpers amqp_client

DEP_EARLY_PLUGINS = rabbit_common/mk/rabbitmq-early-plugin.mk
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk
