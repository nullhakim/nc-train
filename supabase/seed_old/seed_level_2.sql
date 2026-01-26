-- Adding this here ensures it goes to the cloud during 'db push'

INSERT INTO
    public.bravo (id, bravo_1, bravo_2)
VALUES (
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        'bravo_one',
        'bravo_one_description'
    ),
    (
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e',
        'bravo_two',
        'bravo_two_description'
    ),
    (
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f',
        'bravo_three',
        'bravo_three_description'
    );

INSERT INTO
    public.alfa (alfa_1, alfa_2, bravo_id)
VALUES (
        'John',
        'Doe',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f'
    ),
    (
        'Jane',
        'Smith',
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e'
    ),
    (
        'Alice',
        'Johnson',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    ),
    (
        'Bob',
        'Brown',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f'
    ),
    (
        'Charlie',
        'Davis',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    );