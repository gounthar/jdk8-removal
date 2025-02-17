import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime

def create_plugins_evolution_plot(input_csv, output_svg):
    # Read the CSV file
    df = pd.read_csv(input_csv)
    
    # Convert dates to datetime
    df['Date'] = pd.to_datetime(df['Date'])
    
    # Create the plot with a larger figure size
    plt.figure(figsize=(12, 7))
    
    # Plot each metric with different colors and markers
    plt.plot(df['Date'], df['Plugins_Without_Jenkinsfile'], 
             marker='o', label='Without Jenkinsfile', color='#e74c3c')
    plt.plot(df['Date'], df['Plugins_With_Java8'], 
             marker='s', label='With Java 8', color='#2ecc71')
    plt.plot(df['Date'], df['Plugins_Without_Java_Versions'], 
             marker='^', label='Without Java Versions', color='#3498db')
    
    # Customize the plot
    plt.title('Jenkins Plugins Evolution', pad=20, fontsize=14)
    plt.xlabel('Date', labelpad=10)
    plt.ylabel('Number of Plugins', labelpad=10)
    
    # Rotate x-axis labels for better readability
    plt.xticks(rotation=45, ha='right')
    
    # Add grid
    plt.grid(True, linestyle='--', alpha=0.7)
    
    # Add legend
    plt.legend(loc='center left', bbox_to_anchor=(1, 0.5))
    
    # Adjust layout to prevent label cutoff
    plt.tight_layout()
    
    # Save as SVG
    plt.savefig(output_svg, format='svg', bbox_inches='tight')
    plt.close()

if __name__ == "__main__":
    create_plugins_evolution_plot('plugin_evolution.csv', 'plugins_evolution.svg')
