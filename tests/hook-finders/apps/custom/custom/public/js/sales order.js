frappe.ui.form.on("Sales Order", {
	refresh(frm) {
		// add buttons
		frm.add_custom_button("x");
	},
	// validate(frm) {
	// },
	validate: function(frm) {},
	customer: (frm) => {},
	onload: (frm) => {},
	"before_save": function(frm) {},
	'after_save': function(frm) {},
	setup() {},
	on_submit(doc) {},
	async before_submit(frm) {},
	onload_post_render: frm => {},
	after_cancel(frm)
	{
		frm.refresh();
		validate(x);
	},
});
