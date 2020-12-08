class AddUniqueIndexToUsers < ActiveRecord::Migration[5.2]
  def change
    add_index :users, [:username, :provider], unique: true
    add_index :users, [:email, :provider], unique: true
  end
end
