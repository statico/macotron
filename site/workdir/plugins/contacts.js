macotron.plugin({
    title: "Contacts",
    description: "Search your contacts from the launcher.",
});

function paint() {
    const people = macotron.contacts.list();
    macotron.launcher.set(
        "contacts",
        people.map((p) => ({
            id: p.id,
            title: p.name,
            subtitle: p.emails[0] || p.phones[0] || p.organization,
            app: "com.apple.Contacts",
            kind: "Contact",
            onClick: () => {
                if (p.emails[0]) macotron.url.open("mailto:" + p.emails[0]);
                else if (p.phones[0]) macotron.url.open("tel:" + p.phones[0]);
                else macotron.notify.toast("No email or phone");
            },
        }))
    );
}

paint();
macotron.every(60000, paint);
