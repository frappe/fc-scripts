app_name = "custom"

# include js in page
# page_js = {"page" : "public/js/file.js"}

# include js in doctype views
# doctype_js = {"doctype" : "public/js/doctype.js"}
doctype_js = {"Sales Invoice": "public/js/sales_invoice.js"}
doctype_list_js = {"Sales Invoice": "public/js/sales_invoice_list.js"}
doctype_tree_js = {"Account": "public/js/account_tree.js"}
doctype_calendar_js = {"Event": "public/js/event_calendar.js"}
page_js = {"setup-wizard": "public/js/my_wizard.js"}









# doc_events = {
# 	"*": {"on_update": "method"},
# }
doc_events = {
	"Sales Order": {"validate": "custom.so.validate"},
}

# before_request = ["custom.utils.before_request"]
after_job = ["custom.utils.after_job"]
