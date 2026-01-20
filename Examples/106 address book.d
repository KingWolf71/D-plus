// Address Book Database (V1.029.0)
// Practical example: Contacts with multiple addresses and phone numbers
// Uses lists and maps for flexible data storage

#pragma appname "Address-Book"
#pragma decimals 0
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma version on
#pragma ftoi "truncate"
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma ListASM on
#pragma DumpASM off
#pragma asmdecimal on
#pragma ListASM on

print("=================================================");
print("         ADDRESS BOOK DATABASE V1.029.0");
print("=================================================");
print("");

// ============================================
// DATA STRUCTURES
// ============================================

// Address types: 1=Home, 2=Business, 3=Other
// Phone types: 1=Mobile, 2=Home, 3=Business, 4=Fax

struct Address {
    addrType.i;         // 1=Home, 2=Business, 3=Other
    street.s;
    city.s;
    state.s;
    zipCode.s;
    country.s;
}

struct Phone {
    phoneType.i;        // 1=Mobile, 2=Home, 3=Business, 4=Fax
    number.s;
    extension.s;        // For business phones
}

struct Person {
    firstName.s;
    lastName.s;
    email.s;
    company.s;
    jobTitle.s;
    birthday.s;         // Format: YYYY-MM-DD
    notes.s;
}

// ============================================
// GLOBAL STORAGE
// ============================================

// Main contact list - stores Person structs
list contacts.Person;

// Maps for quick lookup by unique key (lastName_firstName)
map contactIndex.i;     // key -> contact position in list

// Separate lists for addresses and phones (linked by contact key)
list addresses.Address;
list phones.Phone;

// Link maps: contact key -> starting index in addresses/phones lists
map addrStartIndex.i;
map addrCount.i;
map phoneStartIndex.i;
map phoneCount.i;

// ============================================
// HELPER FUNCTIONS
// ============================================

func getContactKey.s(firstName.s, lastName.s) {
    return lastName + "_" + firstName;
}

func getAddrTypeName.s(addrType.i) {
    if (addrType == 1) { return "Home"; }
    if (addrType == 2) { return "Business"; }
    return "Other";
}

func getPhoneTypeName.s(phoneType.i) {
    if (phoneType == 1) { return "Mobile"; }
    if (phoneType == 2) { return "Home"; }
    if (phoneType == 3) { return "Business"; }
    if (phoneType == 4) { return "Fax"; }
    return "Other";
}

// ============================================
// DATABASE FUNCTIONS
// ============================================

func addContact(p.Person) {
    key.s = getContactKey(p.firstName, p.lastName);

    // Check if already exists
    if (mapContains(contactIndex, key)) {
        print("ERROR: Contact already exists: ", p.firstName, " ", p.lastName);
        return 0;
    }

    // Get current list position (0-based index)
    pos.i = listSize(contacts);

    // Add to list
    listAdd(contacts, p);

    // Index by key
    mapPut(contactIndex, key, pos);

    // Initialize address/phone counts
    mapPut(addrCount, key, 0);
    mapPut(phoneCount, key, 0);

    return 1;
}

func addAddress(firstName.s, lastName.s, addr.Address) {
    key.s = getContactKey(firstName, lastName);

    if (mapContains(contactIndex, key) == 0) {
        print("ERROR: Contact not found: ", firstName, " ", lastName);
        return 0;
    }

    // Get current address count for this contact
    count.i = mapGet(addrCount, key);

    // If first address, record starting index
    if (count == 0) {
        mapPut(addrStartIndex, key, listSize(addresses));
    }

    // Add address
    listAdd(addresses, addr);
    mapPut(addrCount, key, count + 1);

    return 1;
}

func addPhone(firstName.s, lastName.s, ph.Phone) {
    key.s = getContactKey(firstName, lastName);

    if (mapContains(contactIndex, key) == 0) {
        print("ERROR: Contact not found: ", firstName, " ", lastName);
        return 0;
    }

    // Get current phone count
    count.i = mapGet(phoneCount, key);

    // If first phone, record starting index
    if (count == 0) {
        mapPut(phoneStartIndex, key, listSize(phones));
    }

    // Add phone
    listAdd(phones, ph);
    mapPut(phoneCount, key, count + 1);

    return 1;
}

func printContact(firstName.s, lastName.s) {
    key.s = getContactKey(firstName, lastName);

    if (mapContains(contactIndex, key) == 0) {
        print("Contact not found: ", firstName, " ", lastName);
        return;
    }

    // Get contact from list
    pos.i = mapGet(contactIndex, key);
    listFirst(contacts);
    i = 0;
    while (i < pos) {
        listNext(contacts);
        i = i + 1;
    }

    p.Person = {};
    p = listGet(contacts);

    print("----------------------------------------");
    print("CONTACT: ", p.firstName, " ", p.lastName);
    print("----------------------------------------");
    if (len(p.email) > 0) {
        print("  Email:    ", p.email);
    }
    if (len(p.company) > 0) {
        print("  Company:  ", p.company);
    }
    if (len(p.jobTitle) > 0) {
        print("  Title:    ", p.jobTitle);
    }
    if (len(p.birthday) > 0) {
        print("  Birthday: ", p.birthday);
    }
    if (len(p.notes) > 0) {
        print("  Notes:    ", p.notes);
    }

    // Print addresses
    addrCnt.i = mapGet(addrCount, key);
    if (addrCnt > 0) {
        print("");
        print("  ADDRESSES (", addrCnt, "):");
        startIdx.i = mapGet(addrStartIndex, key);

        // Navigate to starting address
        listFirst(addresses);
        i = 0;
        while (i < startIdx) {
            listNext(addresses);
            i = i + 1;
        }

        // Print each address
        j = 0;
        while (j < addrCnt) {
            addr.Address = {};
            addr = listGet(addresses);
            print("    [", getAddrTypeName(addr.addrType), "]");
            print("      ", addr.street);
            print("      ", addr.city, ", ", addr.state, " ", addr.zipCode);
            if (len(addr.country) > 0) {
                print("      ", addr.country);
            }
            listNext(addresses);
            j = j + 1;
        }
    }

    // Print phones
    phoneCnt.i = mapGet(phoneCount, key);
    if (phoneCnt > 0) {
        print("");
        print("  PHONE NUMBERS (", phoneCnt, "):");
        startIdx = mapGet(phoneStartIndex, key);

        // Navigate to starting phone
        listFirst(phones);
        i = 0;
        while (i < startIdx) {
            listNext(phones);
            i = i + 1;
        }

        // Print each phone
        j = 0;
        while (j < phoneCnt) {
            ph.Phone = {};
            ph = listGet(phones);
            if (len(ph.extension) > 0) {
                print("    [", getPhoneTypeName(ph.phoneType), "] ", ph.number, " ext.", ph.extension);
            } else {
                print("    [", getPhoneTypeName(ph.phoneType), "] ", ph.number);
            }
            listNext(phones);
            j = j + 1;
        }
    }

    print("");
}

func printAllContacts() {
    print("");
    print("=================================================");
    print("              ALL CONTACTS");
    print("=================================================");

    count.i = listSize(contacts);
    print("Total contacts: ", count);
    print("");

    listReset(contacts);
    while (listNext(contacts)) {
        p.Person = {};
        p = listGet(contacts);
        printContact(p.firstName, p.lastName);
    }
}

func printStats() {
    print("");
    print("=== DATABASE STATISTICS ===");
    print("  Total Contacts:  ", listSize(contacts));
    print("  Total Addresses: ", listSize(addresses));
    print("  Total Phones:    ", listSize(phones));
    print("");
}

// ============================================
// POPULATE DATABASE WITH SAMPLE DATA
// ============================================

print("Populating address book with sample data...");
print("");

// --- Contact 1: John Smith ---
person.Person = { };
person.firstName = "John";
person.lastName = "Smith";
person.email = "john.smith@email.com";
person.company = "Tech Solutions Inc.";
person.jobTitle = "Senior Developer";
person.birthday = "1985-03-15";
person.notes = "Met at conference 2024";
addContact(person);

// John's addresses
addr.Address = { };
addr.addrType = 1;  // Home
addr.street = "123 Oak Street";
addr.city = "Springfield";
addr.state = "IL";
addr.zipCode = "62701";
addr.country = "USA";
addAddress("John", "Smith", addr);

addr.addrType = 2;  // Business
addr.street = "456 Corporate Blvd, Suite 300";
addr.city = "Chicago";
addr.state = "IL";
addr.zipCode = "60601";
addr.country = "USA";
addAddress("John", "Smith", addr);

// John's phones
phone.Phone = { };
phone.phoneType = 1;  // Mobile
phone.number = "+1-555-123-4567";
phone.extension = "";
addPhone("John", "Smith", phone);

phone.phoneType = 3;  // Business
phone.number = "+1-555-987-6543";
phone.extension = "215";
addPhone("John", "Smith", phone);

// --- Contact 2: Maria Garcia ---
person.firstName = "Maria";
person.lastName = "Garcia";
person.email = "maria.garcia@company.org";
person.company = "Global Imports LLC";
person.jobTitle = "Operations Manager";
person.birthday = "1990-07-22";
person.notes = "Spanish speaker, prefers email";
addContact(person);

// Maria's addresses
addr.addrType = 1;  // Home
addr.street = "789 Maple Avenue, Apt 4B";
addr.city = "Miami";
addr.state = "FL";
addr.zipCode = "33101";
addr.country = "USA";
addAddress("Maria", "Garcia", addr);

addr.addrType = 2;  // Business
addr.street = "100 Trade Center Drive";
addr.city = "Miami";
addr.state = "FL";
addr.zipCode = "33132";
addr.country = "USA";
addAddress("Maria", "Garcia", addr);

addr.addrType = 3;  // Other (vacation home)
addr.street = "Calle del Sol 42";
addr.city = "San Juan";
addr.state = "PR";
addr.zipCode = "00901";
addr.country = "Puerto Rico";
addAddress("Maria", "Garcia", addr);

// Maria's phones
phone.phoneType = 1;  // Mobile
phone.number = "+1-555-234-5678";
phone.extension = "";
addPhone("Maria", "Garcia", phone);

phone.phoneType = 2;  // Home
phone.number = "+1-555-234-9999";
phone.extension = "";
addPhone("Maria", "Garcia", phone);

phone.phoneType = 3;  // Business
phone.number = "+1-555-800-1234";
phone.extension = "101";
addPhone("Maria", "Garcia", phone);

phone.phoneType = 4;  // Fax
phone.number = "+1-555-800-1235";
phone.extension = "";
addPhone("Maria", "Garcia", phone);

// --- Contact 3: Robert Chen ---
person.firstName = "Robert";
person.lastName = "Chen";
person.email = "rchen@startup.io";
person.company = "NextGen Startup";
person.jobTitle = "CTO";
person.birthday = "1982-11-08";
person.notes = "Angel investor, interested in AI projects";
addContact(person);

// Robert's address (just one)
addr.addrType = 2;  // Business only
addr.street = "1 Innovation Way";
addr.city = "San Francisco";
addr.state = "CA";
addr.zipCode = "94105";
addr.country = "USA";
addAddress("Robert", "Chen", addr);

// Robert's phones
phone.phoneType = 1;  // Mobile
phone.number = "+1-555-345-6789";
phone.extension = "";
addPhone("Robert", "Chen", phone);

// --- Contact 4: Sarah Johnson ---
person.firstName = "Sarah";
person.lastName = "Johnson";
person.email = "sarah.j@freelance.net";
person.company = "";  // Freelancer
person.jobTitle = "Graphic Designer";
person.birthday = "1995-01-30";
person.notes = "Freelance designer, works remotely";
addContact(person);

// Sarah's address
addr.addrType = 1;  // Home/Office
addr.street = "555 Creative Lane";
addr.city = "Portland";
addr.state = "OR";
addr.zipCode = "97201";
addr.country = "USA";
addAddress("Sarah", "Johnson", addr);

// Sarah's phones
phone.phoneType = 1;  // Mobile
phone.number = "+1-555-456-7890";
phone.extension = "";
addPhone("Sarah", "Johnson", phone);

phone.phoneType = 2;  // Home
phone.number = "+1-555-456-1111";
phone.extension = "";
addPhone("Sarah", "Johnson", phone);

// --- Contact 5: David Williams (minimal info) ---
person.firstName = "David";
person.lastName = "Williams";
person.email = "dwilliams@mail.com";
person.company = "";
person.jobTitle = "";
person.birthday = "";
person.notes = "Casual contact";
addContact(person);

// David has only one phone, no address
phone.phoneType = 1;  // Mobile
phone.number = "+1-555-567-8901";
phone.extension = "";
addPhone("David", "Williams", phone);

// ============================================
// DISPLAY ALL DATA
// ============================================

printAllContacts();
printStats();

// ============================================
// DEMONSTRATE LOOKUP
// ============================================

print("=================================================");
print("         LOOKUP DEMONSTRATION");
print("=================================================");
print("");

print("Looking up 'Maria Garcia'...");
printContact("Maria", "Garcia");

print("Looking up 'Robert Chen'...");
printContact("Robert", "Chen");

print("Looking up non-existent contact 'Unknown Person'...");
printContact("Unknown", "Person");

print("");
print("=================================================");
print("         ADDRESS BOOK DEMO COMPLETE");
print("=================================================");
